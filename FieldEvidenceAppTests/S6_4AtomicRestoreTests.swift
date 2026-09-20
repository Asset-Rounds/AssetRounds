import Darwin
import Foundation
import CoreGraphics
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_S6_4AtomicRestoreTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_S6_4AtomicRestoreTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

private final class C45AtomicRestoreCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityRestoresActiveOrHistoricDispositionExactly() {
        XCTAssertEqual(Set(AcceptedLabelSnapshotDispositionV1.allCases), [.activeSourceWorkspace, .historicCloneOrFork])
        XCTAssertEqual(LabelReprintEligibilityV1.activeExactReprint.rawValue, "ACTIVE_EXACT_REPRINT")
        XCTAssertEqual(LabelReprintEligibilityV1.blockedMissingRelease.rawValue, "BLOCKED_MISSING_RELEASE")
    }
}

private final class C30EvidenceContextAnchorS6_4AtomicRestore: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S6_4AtomicRestoreTests: XCTestCase {
    @MainActor
    func testRoundArchiveStagingPreservesVersionAndAuthorityBoundaries() throws {
        let harness = try makeHarness("round-archive-staging")
        defer { try? fileManager.removeItem(at: harness.root) }
        let authority = try harness.factory.makeRestoreGenerationAuthority()
        let originalID = harness.session.generationID
        let digest = String(repeating: "a", count: 64)
        let stagedID = UUID()
        var populated = false
        try harness.factory.createRestoreStagingGeneration(
            id: stagedID, authority: authority, recordsSchemaVersion: 44,
            sourceGenerationID: originalID, archiveProvenanceSHA256: digest
        ) { context in
            let markers = try context.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>())
            XCTAssertEqual(markers.count, 1)
            let marker = try XCTUnwrap(markers.first)
            XCTAssertEqual(marker.schemaVersion, 45)
            populated = true
        }
        XCTAssertTrue(populated)
        let present = try harness.factory.generationPresence(id: stagedID, authority: authority)
        XCTAssertTrue(present.staging)
        XCTAssertFalse(present.installed)
        XCTAssertEqual(try harness.factory.currentGenerationID(authority: authority), originalID)
        try harness.factory.removeRestoreStagingGeneration(id: stagedID, authority: authority)

        // The newly admitted Round version must not bypass provenance or
        // source identity, and versions outside the constructor range deny
        // before creating a generation or invoking the population callback.
        let hostile: [(Int, UUID?, String)] = [
            (0, nil, digest), (53, originalID, digest),
            (44, nil, digest), (44, originalID, "invalid")
        ]
        for (version, sourceID, provenance) in hostile {
            let deniedID = UUID()
            var invoked = false
            XCTAssertThrowsError(try harness.factory.createRestoreStagingGeneration(
                id: deniedID, authority: authority, recordsSchemaVersion: version,
                sourceGenerationID: sourceID, archiveProvenanceSHA256: provenance,
                populate: { _ in invoked = true }
            )) { error in
                XCTAssertEqual(error as? StoreGenerationFailure, .dataPointerInvalid)
            }
            XCTAssertFalse(invoked)
            let absent = try harness.factory.generationPresence(id: deniedID, authority: authority)
            XCTAssertFalse(absent.staging)
            XCTAssertFalse(absent.installed)
            XCTAssertEqual(try harness.factory.currentGenerationID(authority: authority), originalID)
        }
    }

    @MainActor
    func testOwnedGenerationCleanupDoesNotApplyGenerationGrammarToImportPackages() throws {
        let harness = try makeHarness("owned-grammar-import-separation")
        defer { try? fileManager.removeItem(at: harness.root) }
        let authority = try harness.factory.makeRestoreGenerationAuthority()
        let packageName = "inventory-import-package"
        let package = harness.support.appendingPathComponent("FieldEvidenceRestore/staging/\(packageName)")
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("validated import member".utf8).write(to: package.appendingPathComponent("records.json"))
        XCTAssertTrue(try authority.importStagingNames().contains(packageName))
        try authority.removeImportStagingPackage(name: packageName)
        XCTAssertFalse(fileManager.fileExists(atPath: package.path))
        let generationID = uuid("64000000-0000-4000-8000-000000000f01")
        try authority.createStagingGeneration(id: generationID)
        let generation = harness.factory.restoreStagingGenerationURL(id: generationID)
        let unowned = generation.appendingPathComponent("records.json")
        try Data("not a generation member".utf8).write(to: unowned)
        XCTAssertThrowsError(try authority.removeStagingGeneration(id: generationID))
        XCTAssertEqual(try Data(contentsOf: unowned), Data("not a generation member".utf8))
        try assertPhotoRestoreManifestProofAdmitsOnlyExactAuthenticatedPendingPairs()
    }

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
    @MainActor
    func testV23P03C40TypedRowPersistsAsAtomicRestoreUnit() throws {
        let harness = try makeHarness("c40-row")
        defer { try? fileManager.removeItem(at: harness.root) }
        let source = try C40BackupLifecycleTestValues.source(
            workspace: harness.session.workspaceIdentity.workspaceID.rawValue
        )
        harness.session.modelContext.insert(try AuthoritySourceReleaseRow(source))
        try harness.session.modelContext.save()

        let rows = try harness.session.modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows[0].value(), source)
        XCTAssertEqual(
            try AuthorityCriterionCanonicalCodecV1.encode(rows[0].value()),
            try AuthorityCriterionCanonicalCodecV1.encode(source)
        )
    }

    private let fileManager = FileManager.default

    private func assertPhotoRestoreManifestProofAdmitsOnlyExactAuthenticatedPendingPairs() throws {
        let predecessorID = uuid("64000000-0000-4000-8000-00000000f101")
        let generationID = uuid("64000000-0000-4000-8000-00000000f102")
        let restoreID = uuid("64000000-0000-4000-8000-00000000f103")
        let evidenceID = uuid("64000000-0000-4000-8000-00000000f104")
        let otherEvidenceID = uuid("64000000-0000-4000-8000-00000000f105")
        let firstChildID = uuid("64000000-0000-4000-8000-00000000f110")
        let secondChildID = uuid("64000000-0000-4000-8000-00000000f111")
        let originalDigest = String(repeating: "a", count: 64)
        let thumbnailDigest = String(repeating: "b", count: 64)
        let markerDigest = String(repeating: "c", count: 64)
        let bindingDigest = String(repeating: "d", count: 64)
        let modelDigest = String(repeating: "e", count: 64)

        func member(
            evidenceID: UUID,
            leaf: String,
            byteCount: Int,
            digest: String,
            sourcePath: String? = nil
        ) -> CheckRunnerPhotoBackupRestorePlanV1.GenerationMember {
            let canonicalID = evidenceID.uuidString.lowercased()
            let relativePath = ".staging/evidence/\(canonicalID)/\(leaf)"
            return .init(
                entry: .init(
                    byteCount: byteCount,
                    mimeType: leaf == "pair-publication.json"
                        ? "application/json" : "image/jpeg",
                    path: sourcePath ?? "photo-plan/\(canonicalID)/\(leaf)",
                    sha256: digest
                ),
                relativePath: relativePath,
                kind: .staging
            )
        }

        func plan(
            sourceGenerationID: UUID,
            childDraftIDs: [UUID],
            pairLocation: CheckRunnerPhotoBackupPhysicalPlanV1.PairLocation =
                .staged(markerPresent: true),
            members: [CheckRunnerPhotoBackupRestorePlanV1.GenerationMember],
            rawPublications:
                [CheckRunnerPhotoBackupRestorePlanV1.RawPublication] = []
        ) -> CheckRunnerPhotoBackupRestorePlanV1 {
            .init(
                source: .init(
                    appBuild: "restore-proof-test",
                    appVersion: "23",
                    persistentSchemaVersion:
                        PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major,
                    recordsSchemaVersion: 1,
                    sourceGenerationID: sourceGenerationID
                ),
                children: childDraftIDs.map {
                    .init(
                        childDraftID: $0,
                        stageID: $0,
                        physicalEntry: nil,
                        pairLocation: pairLocation,
                        immutableRawPath: nil,
                        entries: members.map(\.entry)
                    )
                },
                rawPublications: rawPublications,
                generationMembers: members,
                metadata: [:]
            )
        }

        let members = [
            member(
                evidenceID: evidenceID,
                leaf: "original.jpg",
                byteCount: 101,
                digest: originalDigest
            ),
            member(
                evidenceID: evidenceID,
                leaf: "thumbnail.jpg",
                byteCount: 37,
                digest: thumbnailDigest
            ),
            member(
                evidenceID: evidenceID,
                leaf: "pair-publication.json",
                byteCount: 73,
                digest: markerDigest
            ),
        ]
        let rawWitnessBytes = Data("restore-proof-raw-witness".utf8)
        let rawItem = try AttachmentStagingItemV1(
            stageID: firstChildID,
            draftID: firstChildID,
            workspaceID: WorkspaceID(
                rawValue: uuid("64000000-0000-4000-8000-00000000f118")
            ),
            attachmentKind: .photo,
            scratchLeaseID: uuid("64000000-0000-4000-8000-00000000f119"),
            expectedByteCount: Int64(rawWitnessBytes.count),
            actualByteCount: Int64(rawWitnessBytes.count),
            contentDigest: try ContentDigestV1(
                algorithm: .sha256,
                hexadecimalValue: StoreMigrationCanonicalJSONV1.sha256(
                    rawWitnessBytes
                )
            ),
            retryClass: .none,
            state: .readyLocal,
            protectionState: .available,
            revision: 1,
            mutationID: try MutationIDV1(
                rawValue: uuid("64000000-0000-4000-8000-00000000f120")
            )
        )
        let physicalEntry = try CheckRunnerPhotoBackupPhysicalEntryV1(
            entry: DraftAttachmentStagingEntryV1(
                item: rawItem,
                relativeDataPath:
                    DraftAttachmentStagingAdapterV1.relativeDataPath(
                        draftID: rawItem.draftID,
                        stageID: rawItem.stageID
                    ),
                mediaType: "image/jpeg",
                updatedAt: Date(timeIntervalSinceReferenceDate: 123)
            )
        )
        let rawPublication = CheckRunnerPhotoBackupRestorePlanV1.RawPublication(
            physicalEntry: physicalEntry,
            payload: .init(
                byteCount: rawWitnessBytes.count,
                mimeType: "application/octet-stream",
                path: "photo-plan/raw.bin",
                sha256: StoreMigrationCanonicalJSONV1.sha256(rawWitnessBytes)
            ),
            witness: .init(
                byteCount: rawWitnessBytes.count,
                mimeType: "application/json",
                path: "photo-plan/raw.json",
                sha256: StoreMigrationCanonicalJSONV1.sha256(rawWitnessBytes)
            ),
            witnessBytes: rawWitnessBytes
        )
        let firstPlan = plan(
            sourceGenerationID: uuid("64000000-0000-4000-8000-00000000f106"),
            childDraftIDs: [firstChildID],
            members: members,
            rawPublications: [rawPublication]
        )
        let duplicateDestinationPlan = plan(
            sourceGenerationID: firstPlan.source.sourceGenerationID!,
            childDraftIDs: [secondChildID],
            members: members.enumerated().map { index, value in
                member(
                    evidenceID: evidenceID,
                    leaf: value.relativePath.split(separator: "/").last.map(String.init)!,
                    byteCount: value.entry.byteCount,
                    digest: value.entry.sha256,
                    sourcePath: "duplicate-source/\(index)"
                )
            }
        )
        let boundEmptyPlan = plan(
            sourceGenerationID: uuid("64000000-0000-4000-8000-00000000f107"),
            childDraftIDs: [],
            members: []
        )
        let proof = try StoreRestoreGenerationManifestProofV1(
            restoreID: restoreID,
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [firstPlan, duplicateDestinationPlan, boundEmptyPlan]
        )
        XCTAssertEqual(proof.recoveryFiles.count, 3)
        XCTAssertEqual(
            proof.recoveryDirectories,
            [
                ".staging",
                ".staging/evidence",
                ".staging/evidence/\(evidenceID.uuidString.lowercased())",
            ]
        )
        XCTAssertEqual(
            try StoreRestoreGenerationManifestProofV1.decodeCanonical(
                from: proof.canonicalData(),
                incumbentPublicationBindingSHA256: bindingDigest,
                resolving: [firstPlan, duplicateDestinationPlan, boundEmptyPlan]
            ),
            proof
        )
        var unknownKeyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: proof.canonicalData())
                as? [String: Any]
        )
        unknownKeyObject["unknown"] = true
        let unknownKeyBytes = try JSONSerialization.data(
            withJSONObject: unknownKeyObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertThrowsError(
            try StoreRestoreGenerationManifestProofV1.decodeCanonical(
                from: unknownKeyBytes,
                incumbentPublicationBindingSHA256: bindingDigest,
                resolving: [firstPlan, duplicateDestinationPlan, boundEmptyPlan]
            )
        )
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [
                firstPlan, duplicateDestinationPlan,
            ]
        ))
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [
                duplicateDestinationPlan, firstPlan, boundEmptyPlan,
            ]
        ))
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: String(repeating: "0", count: 64),
            plans: [firstPlan, duplicateDestinationPlan, boundEmptyPlan]
        ))

        let changedSourcePlan = CheckRunnerPhotoBackupRestorePlanV1(
            source: .init(
                appBuild: "changed-source",
                appVersion: firstPlan.source.appVersion,
                persistentSchemaVersion:
                    firstPlan.source.persistentSchemaVersion,
                replicaID: firstPlan.source.replicaID,
                recordsSchemaVersion: firstPlan.source.recordsSchemaVersion,
                sourceGenerationID: firstPlan.source.sourceGenerationID,
                workspaceID: firstPlan.source.workspaceID
            ),
            children: firstPlan.children,
            rawPublications: firstPlan.rawPublications,
            generationMembers: firstPlan.generationMembers,
            metadata: firstPlan.metadata
        )
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [
                changedSourcePlan, duplicateDestinationPlan, boundEmptyPlan,
            ]
        ))
        let changedChildPlan = CheckRunnerPhotoBackupRestorePlanV1(
            source: firstPlan.source,
            children: firstPlan.children.map {
                .init(
                    childDraftID: $0.childDraftID,
                    stageID: secondChildID,
                    physicalEntry: $0.physicalEntry,
                    pairLocation: $0.pairLocation,
                    immutableRawPath: $0.immutableRawPath,
                    entries: $0.entries
                )
            },
            rawPublications: firstPlan.rawPublications,
            generationMembers: firstPlan.generationMembers,
            metadata: firstPlan.metadata
        )
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [
                changedChildPlan, duplicateDestinationPlan, boundEmptyPlan,
            ]
        ))
        let changedRawPlan = CheckRunnerPhotoBackupRestorePlanV1(
            source: firstPlan.source,
            children: firstPlan.children,
            rawPublications: [.init(
                physicalEntry: rawPublication.physicalEntry,
                payload: rawPublication.payload,
                witness: rawPublication.witness,
                witnessBytes: rawWitnessBytes + Data("changed".utf8)
            )],
            generationMembers: firstPlan.generationMembers,
            metadata: firstPlan.metadata
        )
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [
                changedRawPlan, duplicateDestinationPlan, boundEmptyPlan,
            ]
        ))
        let durableMember = member(
            evidenceID: otherEvidenceID,
            leaf: "original.jpg",
            byteCount: 29,
            digest: String(repeating: "4", count: 64)
        )
        let changedDurablePlan = CheckRunnerPhotoBackupRestorePlanV1(
            source: firstPlan.source,
            children: firstPlan.children,
            rawPublications: firstPlan.rawPublications,
            generationMembers: firstPlan.generationMembers + [.init(
                entry: durableMember.entry,
                relativePath: "evidence/\(otherEvidenceID.uuidString.lowercased())/original.jpg",
                kind: .original
            )],
            metadata: firstPlan.metadata
        )
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [
                changedDurablePlan, duplicateDestinationPlan, boundEmptyPlan,
            ]
        ))
        let changedMetadataPlan = CheckRunnerPhotoBackupRestorePlanV1(
            source: firstPlan.source,
            children: firstPlan.children,
            rawPublications: firstPlan.rawPublications,
            generationMembers: firstPlan.generationMembers,
            metadata: ["photo-plan/metadata.json": Data("changed".utf8)]
        )
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [
                changedMetadataPlan, duplicateDestinationPlan, boundEmptyPlan,
            ]
        ))

        let terminalMembers = [
            CheckRunnerPhotoBackupRestorePlanV1.GenerationMember(
                entry: .init(
                    byteCount: 61,
                    mimeType: "image/jpeg",
                    path: "terminal/original.jpg",
                    sha256: String(repeating: "5", count: 64)
                ),
                relativePath: "evidence/\(otherEvidenceID.uuidString.lowercased())/original.jpg",
                kind: .original
            ),
            CheckRunnerPhotoBackupRestorePlanV1.GenerationMember(
                entry: .init(
                    byteCount: 23,
                    mimeType: "image/jpeg",
                    path: "terminal/thumbnail.jpg",
                    sha256: String(repeating: "6", count: 64)
                ),
                relativePath: "evidence/\(otherEvidenceID.uuidString.lowercased())/thumbnail.jpg",
                kind: .thumbnail
            ),
        ]
        let terminalPlan = plan(
            sourceGenerationID: firstPlan.source.sourceGenerationID!,
            childDraftIDs: [firstChildID],
            pairLocation: .targetOwned,
            members: terminalMembers
        )
        let awaitingRawPlan = plan(
            sourceGenerationID: firstPlan.source.sourceGenerationID!,
            childDraftIDs: [secondChildID],
            pairLocation: .absent,
            members: []
        )
        let emptyRecoveryProof = try StoreRestoreGenerationManifestProofV1(
            restoreID: uuid("64000000-0000-4000-8000-00000000f112"),
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [terminalPlan, awaitingRawPlan]
        )
        XCTAssertEqual(emptyRecoveryProof.recoveryFiles, [])
        XCTAssertEqual(emptyRecoveryProof.recoveryDirectories, [])
        let terminalOnlyProof = try StoreRestoreGenerationManifestProofV1(
            restoreID: uuid("64000000-0000-4000-8000-00000000f115"),
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [terminalPlan]
        )
        let awaitingOnlyProof = try StoreRestoreGenerationManifestProofV1(
            restoreID: uuid("64000000-0000-4000-8000-00000000f116"),
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [awaitingRawPlan]
        )
        XCTAssertEqual(terminalOnlyProof.recoveryFiles, [])
        XCTAssertEqual(awaitingOnlyProof.recoveryFiles, [])
        XCTAssertTrue(try emptyRecoveryProof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [
                terminalPlan, awaitingRawPlan,
            ]
        ))
        XCTAssertEqual(
            try StoreRestoreGenerationManifestProofV1.decodeCanonical(
                from: emptyRecoveryProof.canonicalData(),
                incumbentPublicationBindingSHA256: bindingDigest,
                resolving: [terminalPlan, awaitingRawPlan]
            ),
            emptyRecoveryProof
        )

        let model = try StoreGenerationFileDigestV1(
            relativePath: "model.sqlite",
            byteCount: 211,
            sha256: modelDigest,
            kind: .database
        )
        XCTAssertNoThrow(try StoreGenerationManifestV1(
            generationID: generationID,
            predecessorGenerationID: predecessorID,
            migrationID: uuid("64000000-0000-4000-8000-00000000f113"),
            storeSchemaRelease: PersistentSchemaReleaseRegistryV1.activeRelease,
            semanticSHA256: String(repeating: "7", count: 64),
            frozenIdentityDigest: String(repeating: "8", count: 64),
            files: [model],
            restoreProof: awaitingOnlyProof
        ))
        let terminalGenerationFiles = try terminalMembers.map {
            try StoreGenerationFileDigestV1(
                relativePath: $0.relativePath,
                byteCount: $0.entry.byteCount,
                sha256: $0.entry.sha256,
                kind: $0.kind.protection
            )
        }
        XCTAssertNoThrow(try StoreGenerationManifestV1(
            generationID: generationID,
            predecessorGenerationID: predecessorID,
            migrationID: uuid("64000000-0000-4000-8000-00000000f117"),
            storeSchemaRelease: PersistentSchemaReleaseRegistryV1.activeRelease,
            semanticSHA256: String(repeating: "7", count: 64),
            frozenIdentityDigest: String(repeating: "8", count: 64),
            files: ([model] + terminalGenerationFiles).sorted {
                $0.relativePath < $1.relativePath
            },
            restoreProof: terminalOnlyProof
        ))
        let unexpectedRecoveryFiles = try members.map {
            try StoreGenerationFileDigestV1(
                relativePath: $0.relativePath,
                byteCount: $0.entry.byteCount,
                sha256: $0.entry.sha256,
                kind: .stagingFile
            )
        }
        XCTAssertThrowsError(try StoreGenerationManifestV1(
            generationID: generationID,
            predecessorGenerationID: predecessorID,
            migrationID: uuid("64000000-0000-4000-8000-00000000f114"),
            storeSchemaRelease: PersistentSchemaReleaseRegistryV1.activeRelease,
            semanticSHA256: String(repeating: "7", count: 64),
            frozenIdentityDigest: String(repeating: "8", count: 64),
            files: ([model] + unexpectedRecoveryFiles).sorted {
                $0.relativePath < $1.relativePath
            },
            restoreProof: awaitingOnlyProof
        ))
        let manifest = try StoreGenerationManifestV1(
            generationID: generationID,
            predecessorGenerationID: predecessorID,
            migrationID: uuid("64000000-0000-4000-8000-00000000f108"),
            storeSchemaRelease: PersistentSchemaReleaseRegistryV1.activeRelease,
            semanticSHA256: String(repeating: "f", count: 64),
            frozenIdentityDigest: String(repeating: "0", count: 64),
            files: ([model] + proof.recoveryFiles).sorted {
                $0.relativePath < $1.relativePath
            },
            restoreProof: proof
        )
        XCTAssertEqual(
            try StoreGenerationManifestV1.decodeCanonical(
                from: manifest.canonicalData()
            ),
            manifest
        )
        XCTAssertThrowsError(try StoreGenerationManifestV1(
            generationID: generationID,
            predecessorGenerationID: predecessorID,
            migrationID: manifest.migrationID,
            storeSchemaRelease: manifest.storeSchemaRelease,
            semanticSHA256: manifest.semanticSHA256,
            frozenIdentityDigest: manifest.frozenIdentityDigest,
            files: manifest.files
        ))

        let missingPlan = plan(
            sourceGenerationID: firstPlan.source.sourceGenerationID!,
            childDraftIDs: [firstChildID],
            members: Array(members.dropLast())
        )
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [missingPlan]
        ))
        XCTAssertThrowsError(try StoreRestoreGenerationManifestProofV1.decodeCanonical(
            from: proof.canonicalData(),
            incumbentPublicationBindingSHA256: bindingDigest,
            resolving: [missingPlan]
        ))

        let extraPlan = plan(
            sourceGenerationID: firstPlan.source.sourceGenerationID!,
            childDraftIDs: [firstChildID],
            members: members + [
                member(
                    evidenceID: otherEvidenceID,
                    leaf: "original.jpg",
                    byteCount: 41,
                    digest: String(repeating: "1", count: 64)
                ),
                member(
                    evidenceID: otherEvidenceID,
                    leaf: "thumbnail.jpg",
                    byteCount: 19,
                    digest: String(repeating: "2", count: 64)
                ),
            ]
        )
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [extraPlan]
        ))

        let changedDigestMembers = members.enumerated().map { index, value in
            index == 0
                ? member(
                    evidenceID: evidenceID,
                    leaf: "original.jpg",
                    byteCount: value.entry.byteCount,
                    digest: String(repeating: "3", count: 64)
                )
                : value
        }
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [plan(
                sourceGenerationID: firstPlan.source.sourceGenerationID!,
                childDraftIDs: [firstChildID],
                members: changedDigestMembers
            )]
        ))
        let changedPathMembers = members.map { value in
            member(
                evidenceID: otherEvidenceID,
                leaf: String(value.relativePath.split(separator: "/").last!),
                byteCount: value.entry.byteCount,
                digest: value.entry.sha256
            )
        }
        XCTAssertFalse(try proof.matches(
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [plan(
                sourceGenerationID: firstPlan.source.sourceGenerationID!,
                childDraftIDs: [firstChildID],
                members: changedPathMembers
            )]
        ))
        let conflictingDestinationPlan = plan(
            sourceGenerationID: uuid("64000000-0000-4000-8000-00000000f109"),
            childDraftIDs: [secondChildID],
            members: changedDigestMembers
        )
        XCTAssertThrowsError(try StoreRestoreGenerationManifestProofV1(
            restoreID: restoreID,
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [firstPlan, conflictingDestinationPlan]
        ))

        let invalidPathMember = CheckRunnerPhotoBackupRestorePlanV1.GenerationMember(
            entry: members[0].entry,
            relativePath: ".staging/evidence/\(evidenceID.uuidString.lowercased())/unknown.jpg",
            kind: .staging
        )
        XCTAssertThrowsError(try StoreRestoreGenerationManifestProofV1(
            restoreID: restoreID,
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [plan(
                sourceGenerationID: firstPlan.source.sourceGenerationID!,
                childDraftIDs: [firstChildID],
                members: [invalidPathMember]
            )]
        ))

        XCTAssertThrowsError(try StoreRestoreGenerationManifestProofV1(
            restoreID: restoreID,
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [boundEmptyPlan]
        ))

        XCTAssertThrowsError(try StoreRestoreGenerationManifestProofV1(
            restoreID: restoreID,
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [firstPlan, firstPlan]
        ))
        XCTAssertThrowsError(try StoreRestoreGenerationManifestProofV1(
            restoreID: restoreID,
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [firstPlan, boundEmptyPlan, boundEmptyPlan]
        ))
        XCTAssertThrowsError(try StoreRestoreGenerationManifestProofV1(
            restoreID: restoreID,
            predecessorGenerationID: predecessorID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: bindingDigest,
            plans: [plan(
                sourceGenerationID: firstPlan.source.sourceGenerationID!,
                childDraftIDs: [firstChildID, firstChildID],
                members: members
            )]
        ))

        let migrationCheckpoint = StoreMigrationSourceCheckpointV1(
            files: manifest.files,
            directories: proof.recoveryDirectories,
            frozenIdentityDigest: manifest.frozenIdentityDigest,
            semanticSHA256: manifest.semanticSHA256!
        )
        XCTAssertThrowsError(try migrationCheckpoint.validate())

        let markerPath = ".staging/evidence/\(evidenceID.uuidString.lowercased())/pair-publication.json"
        let markerClassification = try GenerationOwnedPathV1.classify(
            markerPath,
            nodeType: .regularFile
        )
        XCTAssertTrue(markerClassification.recoveryOwned)
        XCTAssertEqual(markerClassification.kind, .stagingFile)
        XCTAssertThrowsError(try GenerationOwnedPathV1.classify(
            String(markerPath.dropFirst(".staging/".count)),
            nodeType: .regularFile
        ))
    }

    @MainActor
    func testGoldenEmptyRestoreSwitchesValidatedGenerationAndRetiresOld() async throws {
        try await assertProofBoundOffActorRestoreFactoryJourney()
        let harness = try makeHarness("golden")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let sourceBytes = try tree(package)
        let validated = try importPackage(package, into: harness.session)
        let oldID = harness.session.generationID

        let service = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                uuid("64000000-0000-0000-0000-000000000101"),
                uuid("64000000-0000-0000-0000-000000000102"),
            ])
        )
        let restored = try await service.restore(
            validatedPackage: validated,
            currentModelContext: harness.session.modelContext,
            currentGenerationID: oldID,
            currentGenerationRootURL: harness.session.generationRootURL
        )

        XCTAssertEqual(restored.generationID, uuid("64000000-0000-0000-0000-000000000101"))
        XCTAssertEqual(try harness.factory.currentGenerationID(), restored.generationID)
        XCTAssertEqual(try harness.factory.retiredGenerationIDs(), [oldID])
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Report>()), 0)
        XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support.appendingPathComponent(
                "FieldEvidenceRestore/restore.json"
            ).path
        ))
        XCTAssertEqual(try tree(package), sourceBytes)

        let reopened = try harness.factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, restored.generationID)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
    }

    @MainActor
    func testRestoreAccessDenialBeforePrivateReadsLeavesImportedStateUntouched() async throws {
        let harness = try makeHarness("restore-access-initial-denial")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let supportBefore = try tree(harness.support)
        var validationCalls = 0
        let service = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([UUID(), UUID()])
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL,
                validateAccess: {
                    validationCalls += 1
                    throw AppAccessContractFailureV1.accessDenied
                }
            )
        } verify: { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }

        XCTAssertEqual(validationCalls, 1)
        XCTAssertEqual(try harness.factory.currentGenerationID(), harness.session.generationID)
        XCTAssertEqual(try tree(harness.support), supportBefore)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: harness.support).load())
    }

    @MainActor
    func testRestoreAccessAuthorizedCallerCompletesPhysicalEmptyInstall() async throws {
        let harness = try makeHarness("restore-access-authorized")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        var validationCalls = 0
        let newGenerationID = uuid("64000000-0000-0000-0000-000000000a11")
        let service = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([newGenerationID, UUID()])
        )

        let restored = try await service.restore(
            validatedPackage: validated,
            currentModelContext: harness.session.modelContext,
            currentGenerationID: harness.session.generationID,
            currentGenerationRootURL: harness.session.generationRootURL,
            validateAccess: { validationCalls += 1 }
        )

        XCTAssertEqual(restored.generationID, newGenerationID)
        XCTAssertGreaterThan(validationCalls, 1)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: harness.support).load())
    }

    @MainActor
    func testRestoreAccessRejectsRevokedAndRegrantedGateAfterSuspendedDocumentResolution() async throws {
        let source = try makeHarness("restore-access-aba-source")
        let target = try makeHarness("restore-access-aba-target")
        defer {
            try? fileManager.removeItem(at: source.root)
            try? fileManager.removeItem(at: target.root)
        }
        let accessiblePackage = try await makeAccessibleDocumentPackage(in: source.root)
        let package = accessiblePackage.package
        let validated = try importPackage(package, into: target.session)
        XCTAssertEqual(validated.records.accessibleDocumentAssessments.count, 1)

        let fallbackBefore = try tree(target.support)
        var fallbackValidationCalls = 0
        let missingResolverService = try BackupRestoreService(
            applicationSupportURL: target.support,
            makeUUID: sequence([UUID(), UUID()])
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await missingResolverService.restore(
                validatedPackage: validated,
                currentModelContext: target.session.modelContext,
                currentGenerationID: target.session.generationID,
                currentGenerationRootURL: target.session.generationRootURL,
                validateAccess: {
                    fallbackValidationCalls += 1
                    guard fallbackValidationCalls == 1 else {
                        throw AppAccessContractFailureV1.accessDenied
                    }
                }
            )
        } verify: { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertEqual(fallbackValidationCalls, 2)
        XCTAssertEqual(try tree(target.support), fallbackBefore)

        let resolver = S64SuspendingAccessibleDocumentResolver(tree: accessiblePackage.tree)
        let gate = AppAccessGateV1(
            setting: .absentDisabled,
            authentication: S64NoopAuthentication(),
            clock: S64IdentityClock(),
            identifiers: S64IdentityIDs()
        )
        let token = try await gate.beginContentRead(for: .backupImport)
        let supportBefore = try tree(target.support)
        let service = try BackupRestoreService(
            applicationSupportURL: target.support,
            makeUUID: sequence([UUID(), UUID()]),
            accessibleDocumentTreeResolver: resolver
        )
        let restore = Task { @MainActor in
            try await service.restore(
                validatedPackage: validated,
                currentModelContext: target.session.modelContext,
                currentGenerationID: target.session.generationID,
                currentGenerationRootURL: target.session.generationRootURL,
                validateAccess: {
                    try await gate.validateContentRead(token, for: .backupImport)
                }
            )
        }
        await resolver.waitUntilRequested()
        await gate.sceneBecameInactive()
        await gate.sceneBecameActive()
        let regrantedToken = try await gate.beginContentRead(for: .backupImport)
        try await gate.validateContentRead(regrantedToken, for: .backupImport)
        await resolver.resume()

        await XCTAssertThrowsErrorAsync {
            _ = try await restore.value
        } verify: { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertEqual(try target.factory.currentGenerationID(), target.session.generationID)
        XCTAssertEqual(try tree(target.support), supportBefore)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: target.support).load())
    }

    @MainActor
    func testInterruptionMatrixRecoversOnlyOldOrFullyValidatedNew() async throws {
        let oldOutcome: Set<BackupRestoreFailurePoint> = [
            .beforePreparedWrite,
            .afterPreparedWrite,
            .beforeGenerationInstall,
            .afterGenerationInstall,
            .beforePointerSwitch,
        ]
        for (offset, point) in BackupRestoreFailurePoint.allCases.enumerated() {
            let harness = try makeHarness("phase-\(offset)")
            defer { try? fileManager.removeItem(at: harness.root) }
            let package = try makeSourcePackage(in: harness.root, name: "source")
            let validated = try importPackage(package, into: harness.session)
            let oldID = harness.session.generationID
            let newID = UUID(
                uuid: (
                    0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    UInt8(0x40 + offset), UInt8(0x50 + offset)
                )
            )
            let service = try BackupRestoreService(
                applicationSupportURL: harness.support,
                makeUUID: sequence([newID, UUID()]),
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point)
            )
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(
                    validatedPackage: validated,
                    currentModelContext: harness.session.modelContext,
                    currentGenerationID: oldID,
                    currentGenerationRootURL: harness.session.generationRootURL
                )
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
            }

            let portableSidecarURL = harness.support.appendingPathComponent(
                "FieldEvidenceRestore/portable-exchange-restore.json",
                isDirectory: false
            )
            if point == .beforePointerSwitch {
                XCTAssertTrue(fileManager.fileExists(atPath: portableSidecarURL.path))
                XCTAssertEqual(try harness.factory.currentGenerationID(), oldID)
            } else if point == .afterPointerSwitch {
                XCTAssertTrue(fileManager.fileExists(atPath: portableSidecarURL.path))
                XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
            }

            let recovery = try BackupRestoreService(
                applicationSupportURL: harness.support
            )
            if point == .afterPointerSwitch {
                let exactSidecar = try Data(contentsOf: portableSidecarURL)
                var hostileSidecar = exactSidecar
                hostileSidecar.append(0x20)
                try hostileSidecar.write(to: portableSidecarURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: portableSidecarURL)
                XCTAssertThrowsError(try recovery.reconcileAtStartup())
                try exactSidecar.write(to: portableSidecarURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: portableSidecarURL)
            }
            let recoveredNew = try await recovery
                .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            let expectedID = oldOutcome.contains(point) ? oldID : newID
            XCTAssertEqual(try harness.factory.currentGenerationID(), expectedID, "\(point)")
            if oldOutcome.contains(point) {
                XCTAssertNil(recoveredNew, "\(point)")
                XCTAssertTrue(BackupRestoreService.isEmptyCurrent(
                    harness.session.modelContext
                ))
            } else {
                XCTAssertEqual(recoveredNew?.generationID, newID, "\(point)")
                XCTAssertEqual(
                    try XCTUnwrap(recoveredNew).modelContext.fetchCount(
                        FetchDescriptor<Asset>()
                    ),
                    1,
                    "\(point)"
                )
            }
            let noFurtherRecovery = try await recovery
                .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            XCTAssertNil(noFurtherRecovery, "\(point)")
            XCTAssertFalse(fileManager.fileExists(atPath: portableSidecarURL.path), "\(point)")
            XCTAssertFalse(fileManager.fileExists(
                atPath: harness.support.appendingPathComponent(
                    "FieldEvidenceRestore/restore.json"
                ).path
            ))
            XCTAssertTrue(fileManager.fileExists(
                atPath: harness.factory.installedGenerationURL(id: oldID).path
            ))
        }
    }

    @MainActor
    func testDirtyNonemptyAndImpossibleRecoveryFailClosed() async throws {
        let dirty = try makeHarness("dirty")
        defer { try? fileManager.removeItem(at: dirty.root) }
        let package = try makeSourcePackage(in: dirty.root, name: "source")
        let validated = try importPackage(package, into: dirty.session)
        dirty.session.modelContext.insert(Site(label: "Unsaved"))
        let service = try BackupRestoreService(applicationSupportURL: dirty.support)
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: dirty.session.modelContext,
                currentGenerationID: dirty.session.generationID,
                currentGenerationRootURL: dirty.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .contextHasChanges)
        }
        XCTAssertEqual(try dirty.factory.currentGenerationID(), dirty.session.generationID)
        dirty.session.modelContext.rollback()
        try BackupImportService(
            generationRootURL: dirty.session.generationRootURL,
            scopedAccess: .alreadyAuthorized
        ).discard(validated)

        let malformed = try makeHarness("impossible")
        defer { try? fileManager.removeItem(at: malformed.root) }
        let missingNew = uuid("64000000-0000-0000-0000-000000000301")
        let intent = RestoreIntentV1(
            newGenerationID: missingNew,
            newGenerationRelativePath:
                "FieldEvidenceData/generations/\(missingNew.uuidString.lowercased())",
            oldGenerationID: malformed.session.generationID,
            phase: .generationInstalled,
            restoreID: uuid("64000000-0000-0000-0000-000000000302"),
            schemaVersion: 1,
            stagingGenerationRelativePath:
                "FieldEvidenceRestore/generations/\(missingNew.uuidString.lowercased())"
        )
        let store = try RestoreIntentStore(applicationSupportURL: malformed.support)
        try store.create(intent)
        let before = try tree(malformed.session.generationRootURL)
        XCTAssertThrowsError(try BackupRestoreService(
            applicationSupportURL: malformed.support
        ).reconcileAtStartup())
        XCTAssertEqual(try malformed.factory.currentGenerationID(), malformed.session.generationID)
        XCTAssertEqual(try tree(malformed.session.generationRootURL), before)
        XCTAssertEqual(try store.load(), intent)
    }

    @MainActor
    func testRecoveryRejectsReplacedRestoreGenerationAncestorWithoutDeleting() async throws {
        let harness = try makeHarness("ancestor-replacement")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000401")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000402"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterPreparedWrite
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }

        let recovery = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let canonicalParent = harness.support.appendingPathComponent(
            "FieldEvidenceRestore/generations",
            isDirectory: true
        )
        let detachedParent = harness.support.appendingPathComponent(
            "FieldEvidenceRestore/generations.detached",
            isDirectory: true
        )
        try fileManager.moveItem(at: canonicalParent, to: detachedParent)
        try fileManager.createDirectory(
            at: canonicalParent,
            withIntermediateDirectories: false
        )
        let marker = canonicalParent.appendingPathComponent("replacement.marker")
        let markerBytes = Data("unowned".utf8)
        try markerBytes.write(to: marker)

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(
            try harness.factory.currentGenerationID(),
            harness.session.generationID
        )
        XCTAssertTrue(fileManager.fileExists(atPath: detachedParent
            .appendingPathComponent(newID.uuidString.lowercased()).path))
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertNotNil(try RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load())
    }

    @MainActor
    func testRecoveryRejectsUnexpectedInstalledGenerationBytesWithoutAdoption() async throws {
        let harness = try makeHarness("unexpected-installed-byte")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000501")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000502"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }

        let unexpected = harness.factory.installedGenerationURL(id: newID)
            .appendingPathComponent("unexpected.bin")
        let unexpectedBytes = Data("ambiguous".utf8)
        try unexpectedBytes.write(to: unexpected)
        let recovery = try BackupRestoreService(
            applicationSupportURL: harness.support
        )

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(
            try harness.factory.currentGenerationID(),
            harness.session.generationID
        )
        XCTAssertEqual(try Data(contentsOf: unexpected), unexpectedBytes)
        XCTAssertEqual(
            try RestoreIntentStore(applicationSupportURL: harness.support).load()?.phase,
            .generationInstalled
        )
    }

    @MainActor
    func testRecoveryRejectsReplacedDataAncestorBeforePointerMutation() async throws {
        let harness = try makeHarness("data-ancestor-replacement")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000601")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000602"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }

        let recovery = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let canonicalData = harness.support.appendingPathComponent(
            "FieldEvidenceData",
            isDirectory: true
        )
        let detachedData = harness.support.appendingPathComponent(
            "FieldEvidenceData.detached",
            isDirectory: true
        )
        try fileManager.moveItem(at: canonicalData, to: detachedData)
        let detachedBefore = try tree(detachedData)
        try fileManager.createDirectory(
            at: canonicalData,
            withIntermediateDirectories: false
        )
        let marker = canonicalData.appendingPathComponent("replacement.marker")
        let markerBytes = Data("unowned data root".utf8)
        try markerBytes.write(to: marker)

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(try tree(detachedData), detachedBefore)
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertEqual(
            try RestoreIntentStore(applicationSupportURL: harness.support).load()?.phase,
            .generationInstalled
        )
    }

    @MainActor
    func testRecoveryResumesExactCurrentPointerPreRenameTemp() async throws {
        let harness = try makeHarness("current-pointer-temp")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000701")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000702"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let temporary = harness.support.appendingPathComponent(
            "FieldEvidenceData/.current.json.restore-next"
        )
        try Data(
            "{\"generationID\":\"\(newID.uuidString.lowercased())\",\"schemaVersion\":1}"
                .utf8
        ).write(to: temporary, options: .withoutOverwriting)

        let recovered = try BackupRestoreService(
            applicationSupportURL: harness.support
        ).reconcileAtStartup()
        XCTAssertEqual(recovered?.generationID, newID)
        XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
        XCTAssertFalse(fileManager.fileExists(atPath: temporary.path))
    }

    @MainActor
    func testRecoveryResumesExactRetiredPointerPreRenameTemp() async throws {
        let harness = try makeHarness("retired-pointer-temp")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let oldID = harness.session.generationID
        let newID = uuid("64000000-0000-0000-0000-000000000801")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000802"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterNewGenerationValidation
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: oldID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let temporary = harness.support.appendingPathComponent(
            "FieldEvidenceData/.retired.json.restore-next"
        )
        try Data(
            "{\"generationIDs\":[\"\(oldID.uuidString.lowercased())\"],\"schemaVersion\":1}"
                .utf8
        ).write(to: temporary, options: .withoutOverwriting)

        let recovered = try BackupRestoreService(
            applicationSupportURL: harness.support
        ).reconcileAtStartup()
        XCTAssertEqual(recovered?.generationID, newID)
        XCTAssertEqual(try harness.factory.retiredGenerationIDs(), [oldID])
        XCTAssertFalse(fileManager.fileExists(atPath: temporary.path))
    }

    @MainActor
    func testRecoveryRejectsImpossibleRetiredStateBeforeMutation() async throws {
        let harness = try makeHarness("retired-state-mismatch")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let oldID = harness.session.generationID
        let newID = uuid("64000000-0000-0000-0000-000000000901")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000902"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: oldID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let dataRoot = harness.support.appendingPathComponent("FieldEvidenceData")
        let retiredURL = dataRoot.appendingPathComponent("retired.json")
        try Data(
            "{\"generationIDs\":[\"\(oldID.uuidString.lowercased())\"],\"schemaVersion\":1}"
                .utf8
        ).write(to: retiredURL, options: .atomic)
        let before = try tree(dataRoot)
        let expectedIntent = try XCTUnwrap(RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load())

        XCTAssertThrowsError(try BackupRestoreService(
            applicationSupportURL: harness.support
        ).reconcileAtStartup())
        XCTAssertEqual(try tree(dataRoot), before)
        XCTAssertEqual(
            try RestoreIntentStore(applicationSupportURL: harness.support).load(),
            expectedIntent
        )
    }

    @MainActor
    func testRecoveryRejectsExtraInstalledOrStagedGenerationBeforeMutation() async throws {
        for extraIsInstalled in [false, true] {
            let harness = try makeHarness(
                extraIsInstalled ? "extra-installed" : "extra-staged"
            )
            defer { try? fileManager.removeItem(at: harness.root) }
            let package = try makeSourcePackage(in: harness.root, name: "source")
            let validated = try importPackage(package, into: harness.session)
            let newID = extraIsInstalled
                ? uuid("64000000-0000-0000-0000-000000000a01")
                : uuid("64000000-0000-0000-0000-000000000b01")
            let restore = try BackupRestoreService(
                applicationSupportURL: harness.support,
                makeUUID: sequence([
                    newID,
                    extraIsInstalled
                        ? uuid("64000000-0000-0000-0000-000000000a02")
                        : uuid("64000000-0000-0000-0000-000000000b02"),
                ]),
                failureInjection: BackupRestoreFailureInjection(
                    failOnceAt: .afterPreparedWrite
                )
            )
            await XCTAssertThrowsErrorAsync {
                _ = try await restore.restore(
                    validatedPackage: validated,
                    currentModelContext: harness.session.modelContext,
                    currentGenerationID: harness.session.generationID,
                    currentGenerationRootURL: harness.session.generationRootURL
                )
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
            }

            let extraID = extraIsInstalled
                ? uuid("64000000-0000-0000-0000-000000000a03")
                : uuid("64000000-0000-0000-0000-000000000b03")
            let parent = extraIsInstalled
                ? harness.support.appendingPathComponent(
                    "FieldEvidenceData/generations",
                    isDirectory: true
                )
                : harness.support.appendingPathComponent(
                    "FieldEvidenceRestore/generations",
                    isDirectory: true
                )
            let extra = parent.appendingPathComponent(
                extraID.uuidString.lowercased(),
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: extra,
                withIntermediateDirectories: false
            )
            try Data("unowned".utf8).write(
                to: extra.appendingPathComponent("marker")
            )
            let recovery = try BackupRestoreService(
                applicationSupportURL: harness.support
            )
            let before = try tree(harness.support)
            let intentBefore = try RestoreIntentStore(
                applicationSupportURL: harness.support
            ).load()

            XCTAssertThrowsError(try recovery.reconcileAtStartup())
            XCTAssertEqual(try tree(harness.support), before)
            XCTAssertEqual(
                try RestoreIntentStore(applicationSupportURL: harness.support).load(),
                intentBefore
            )
        }
    }

    @MainActor
    func testPreparedRecoveryRejectsUnexpectedStagedMemberWithoutDeletion() async throws {
        let harness = try makeHarness("unexpected-staged-member")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000c01")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000c02"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterPreparedWrite
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let unexpected = harness.factory.restoreStagingGenerationURL(id: newID)
            .appendingPathComponent("zz-unexpected.bin")
        try Data("ambiguous staged bytes".utf8).write(to: unexpected)
        let recovery = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let before = try tree(harness.support)
        let intentBefore = try RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load()

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(try tree(harness.support), before)
        XCTAssertEqual(
            try RestoreIntentStore(applicationSupportURL: harness.support).load(),
            intentBefore
        )
    }

    @MainActor
    func testActiveEraseAuthorityBlocksRestoreWithoutMutation() async throws {
        let harness = try makeHarness("active-erase")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let packageBefore = try tree(package)
        let validated = try importPackage(package, into: harness.session)
        let eraseRoot = harness.support.appendingPathComponent(
            "FieldEvidenceErase",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: eraseRoot,
            withIntermediateDirectories: false
        )
        try Data("{\"schemaVersion\":1}".utf8).write(
            to: eraseRoot.appendingPathComponent("erase.json")
        )
        let service = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let supportBefore = try tree(harness.support)

        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { _ in }
        XCTAssertEqual(try tree(harness.support), supportBefore)
        XCTAssertEqual(try tree(package), packageBefore)
        XCTAssertEqual(
            try harness.factory.currentGenerationID(),
            harness.session.generationID
        )
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load())
    }

    @MainActor
    func testExtraImportStageBlocksRestoreWithoutMutation() async throws {
        let harness = try makeHarness("extra-import-stage")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let packageBefore = try tree(package)
        let validated = try importPackage(package, into: harness.session)
        let extra = validated.stagedPackageURL.deletingLastPathComponent()
            .appendingPathComponent(
                "64000000-0000-0000-0000-000000000d01.fieldrecordbackup",
                isDirectory: true
            )
        try fileManager.copyItem(at: validated.stagedPackageURL, to: extra)
        let service = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let supportBefore = try tree(harness.support)

        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { _ in }
        XCTAssertEqual(try tree(harness.support), supportBefore)
        XCTAssertEqual(try tree(package), packageBefore)
        XCTAssertEqual(
            try harness.factory.currentGenerationID(),
            harness.session.generationID
        )
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load())
    }
}

private final class C27S64TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension S6_4AtomicRestoreTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension S6_4AtomicRestoreTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistent: 21, records: 20)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.liveRestorePermitted)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C18PromotionBundleKeepsOldOrNewInterruptionPolicy() throws {
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.interruption,
            "OLD_COMPLETE_OR_NEW_COMPLETE_NEVER_HYBRID"
        )
        XCTAssertTrue(PackageSandboxCheckKindV1.allCases.contains(.backupRestore))
        XCTAssertGreaterThan(MemoryLayout<PackagePromotionAtomicBundleV1>.size, 0)
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C36RestorePublicationReceiptRequiresCanonicalCommit() throws {
        let receipt = try DraftAttachmentRestorePublicationReceiptV1(restoreID:UUID(),workspaceID:WorkspaceID(rawValue:UUID()),sourceManifestSHA256:String(repeating:"a",count:64),adoptedStageIDs:[UUID()],reusedStageIDs:[],publishedAt:Date(timeIntervalSince1970:1))
        try receipt.validate()
        XCTAssertFalse(receipt.atomicAcrossRoots)
        XCTAssertTrue(receipt.canonicalCommitRequired)
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C15AtomicRestoreRoundTripsAllPacketRowsTogether() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_164)
        let manifest = try WorkPacketManifestRow(fixture.manifest).value()
        let claim = try WorkItemClaimRow(fixture.claim).value()
        let lease = try WorkLeaseRow(fixture.lease).value()
        let release = try WorkReleaseRow(fixture.completedRelease).value()
        let handoff = try WorkHandoffRow(fixture.handoff).value()
        XCTAssertEqual(manifest, fixture.manifest)
        XCTAssertEqual(claim, fixture.claim)
        XCTAssertEqual(lease, fixture.lease)
        XCTAssertEqual(release, fixture.completedRelease)
        XCTAssertEqual(handoff, fixture.handoff)
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C13AtomicRestoreRebindsCompleteAssuranceBundle() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_640)
        let destination = C13EvidenceAssuranceTestSupportV1.workspace(51_641)
        let visibility = try fixture.routineVisibility.rebound(to: destination)
        let link = try fixture.customerLink.rebound(to: destination, visibility: visibility)
        let preview = try fixture.customerPreview.rebound(to: destination, links: [link])
        let manifest = try fixture.customerManifest.rebound(to: destination, preview: preview)
        let attestation = try fixture.customerAttestation.rebound(to: destination, manifest: manifest)

        XCTAssertEqual(visibility.workspaceID, destination)
        XCTAssertEqual(link.workspaceID, destination)
        XCTAssertEqual(preview.workspaceID, destination)
        XCTAssertEqual(manifest.workspaceID, destination)
        XCTAssertEqual(attestation.workspaceID, destination)
        XCTAssertEqual(attestation.manifestID, manifest.manifestID)
        try attestation.validate(manifest: manifest)
    }
}

private extension S6_4AtomicRestoreTests {
    struct Harness {
        let root: URL
        let support: URL
        let factory: StoreGenerationFactory
        let session: StoreGenerationSession
    }

    struct FileFact: Equatable {
        let path: String
        let bytes: Data
    }

    enum FixtureError: Error { case invalid, publicationDenied }

    @MainActor
    func makeHarness(_ name: String) throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_4-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        return Harness(root: root, support: support, factory: factory, session: session)
    }

    @MainActor
    func assertProofBoundOffActorRestoreFactoryJourney() async throws {
        let harness = try makeHarness("proof-bound-off-actor-factory")
        defer { try? fileManager.removeItem(at: harness.root) }
        let authority = try harness.factory.makeRestoreGenerationAuthority()
        let oldID = harness.session.generationID
        let newID = uuid("64000000-0000-4000-8000-00000000fa01")
        let evidenceID = uuid("64000000-0000-4000-8000-00000000fa02")
        let childID = uuid("64000000-0000-4000-8000-00000000fa03")
        try harness.factory.createRestoreStagingGeneration(
            id: newID,
            authority: authority,
            recordsSchemaVersion:
                C05EvidenceCurationMigrationBoundaryV1.currentRecordsSchemaVersion,
            sourceGenerationID: oldID,
            archiveProvenanceSHA256: String(repeating: "a", count: 64),
            populate: { _ in }
        )
        let stagingRoot = harness.factory.restoreStagingGenerationURL(id: newID)
        let pairRoot = stagingRoot
            .appendingPathComponent(".staging/evidence", isDirectory: true)
            .appendingPathComponent(
                evidenceID.uuidString.lowercased(),
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: pairRoot,
            withIntermediateDirectories: true
        )
        let original = Data("off-actor-original".utf8)
        let thumbnail = Data("off-actor-thumbnail".utf8)
        let originalURL = pairRoot.appendingPathComponent("original.jpg")
        let thumbnailURL = pairRoot.appendingPathComponent("thumbnail.jpg")
        try original.write(to: originalURL)
        try thumbnail.write(to: thumbnailURL)
        func entry(_ name: String, _ bytes: Data) -> V4BackupEntryV1 {
            .init(
                byteCount: bytes.count,
                mimeType: "image/jpeg",
                path: "factory-fixture/\(name)",
                sha256: StoreMigrationCanonicalJSONV1.sha256(bytes)
            )
        }
        let originalEntry = entry("original.jpg", original)
        let thumbnailEntry = entry("thumbnail.jpg", thumbnail)
        let members = [
            CheckRunnerPhotoBackupRestorePlanV1.GenerationMember(
                entry: originalEntry,
                relativePath: ".staging/evidence/\(evidenceID.uuidString.lowercased())/original.jpg",
                kind: .staging
            ),
            CheckRunnerPhotoBackupRestorePlanV1.GenerationMember(
                entry: thumbnailEntry,
                relativePath: ".staging/evidence/\(evidenceID.uuidString.lowercased())/thumbnail.jpg",
                kind: .staging
            ),
        ]
        let plan = CheckRunnerPhotoBackupRestorePlanV1(
            source: .init(
                appBuild: "factory-fixture",
                appVersion: "23",
                persistentSchemaVersion:
                    PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major,
                recordsSchemaVersion:
                    C05EvidenceCurationMigrationBoundaryV1.currentRecordsSchemaVersion,
                sourceGenerationID: oldID
            ),
            children: [.init(
                childDraftID: childID,
                stageID: childID,
                physicalEntry: nil,
                pairLocation: .staged(markerPresent: false),
                immutableRawPath: nil,
                entries: [originalEntry, thumbnailEntry]
            )],
            rawPublications: [],
            generationMembers: members,
            metadata: [:]
        )
        let proof = try StoreRestoreGenerationManifestProofV1(
            restoreID: uuid("64000000-0000-4000-8000-00000000fa04"),
            predecessorGenerationID: oldID,
            generationID: newID,
            incumbentPublicationBindingSHA256: String(repeating: "b", count: 64),
            plans: [plan]
        )

        func protectAndSnapshot()
            async throws -> StoreRestoreGenerationFileSnapshotV1 {
            try authority.protectStagingGeneration(id: newID, requireModel: true)
            let identity = try authority.restoreGenerationRootIdentity(
                id: newID,
                staging: true
            )
            return try await harness.factory.prepareRestoreGenerationFileSnapshot(
                generationID: newID,
                staging: true,
                expectedRootIdentity: identity,
                restoreProof: proof
            )
        }

        var stagingSnapshot = try await protectAndSnapshot()
        XCTAssertThrowsError(try harness.factory
            .prepareRestoreStagingGenerationManifest(
                expectedOldID: oldID,
                newID: newID,
                restoreProof: proof,
                authority: authority
            ))

        let movedURL = pairRoot.appendingPathComponent("original-moved.jpg")
        try fileManager.moveItem(at: originalURL, to: movedURL)
        XCTAssertThrowsError(try harness.factory
            .prepareRestoreStagingGenerationManifest(
                expectedOldID: oldID,
                newID: newID,
                restoreProof: proof,
                restoreFileSnapshot: stagingSnapshot,
                authority: authority
            ))
        try fileManager.moveItem(at: movedURL, to: originalURL)
        stagingSnapshot = try await protectAndSnapshot()

        let markerURL = pairRoot.appendingPathComponent("pair-publication.json")
        try Data("{}".utf8).write(to: markerURL)
        XCTAssertThrowsError(try harness.factory
            .prepareRestoreStagingGenerationManifest(
                expectedOldID: oldID,
                newID: newID,
                restoreProof: proof,
                restoreFileSnapshot: stagingSnapshot,
                authority: authority
            ))
        try fileManager.removeItem(at: markerURL)
        stagingSnapshot = try await protectAndSnapshot()

        let changed = Data("off-actor-ORIGINAL".utf8)
        XCTAssertEqual(changed.count, original.count)
        let writer = try FileHandle(forWritingTo: originalURL)
        try writer.write(contentsOf: changed)
        try writer.synchronize()
        try writer.close()
        XCTAssertThrowsError(try harness.factory
            .prepareRestoreStagingGenerationManifest(
                expectedOldID: oldID,
                newID: newID,
                restoreProof: proof,
                restoreFileSnapshot: stagingSnapshot,
                authority: authority
            ))
        let restoring = try FileHandle(forWritingTo: originalURL)
        try restoring.write(contentsOf: original)
        try restoring.synchronize()
        try restoring.close()
        stagingSnapshot = try await protectAndSnapshot()

        let manifestDigest = try harness.factory
            .prepareRestoreStagingGenerationManifest(
                expectedOldID: oldID,
                newID: newID,
                restoreProof: proof,
                restoreFileSnapshot: stagingSnapshot,
                authority: authority
            )
        try harness.factory.installRestoreStagingGeneration(
            id: newID,
            restoreProof: proof,
            restoreFileSnapshot: stagingSnapshot,
            authority: authority
        )
        XCTAssertThrowsError(try harness.factory
            .requireInstalledRestoreGenerationSnapshot(
                expectedOldID: oldID,
                generationID: newID,
                expectedManifestDigest: manifestDigest,
                restoreProof: proof,
                restoreFileSnapshot: stagingSnapshot,
                authority: authority
            ))
        let coldAuthority = try harness.factory.makeRestoreGenerationAuthority()
        let installedIdentity = try coldAuthority.restoreGenerationRootIdentity(
            id: newID,
            staging: false
        )
        let installedSnapshot = try await harness.factory
            .prepareRestoreGenerationFileSnapshot(
                generationID: newID,
                staging: false,
                expectedRootIdentity: installedIdentity,
                restoreProof: proof
            )
        let expectedCurrentPointer = try harness.factory
            .currentGenerationPointerV3(
                expectedGenerationID: oldID,
                authority: coldAuthority
            )
        var publicationValidationRan = false
        do {
            try harness.factory.switchCurrentGeneration(
                expected: oldID,
                to: newID,
                expectedCurrentPointer: expectedCurrentPointer,
                identity: harness.session.workspaceIdentity,
                knownReplicaIDs: [harness.session.workspaceIdentity.replicaID],
                preparedGenerationManifestSHA256: manifestDigest,
                restoreProof: proof,
                restoreFileSnapshot: installedSnapshot,
                authority: coldAuthority,
                publicationValidation: {
                    publicationValidationRan = true
                    throw FixtureError.publicationDenied
                }
            )
            XCTFail("publication denial must prevent the pointer switch")
        } catch FixtureError.publicationDenied {}
        XCTAssertTrue(publicationValidationRan)
        XCTAssertEqual(
            try harness.factory.currentGenerationID(authority: coldAuthority),
            oldID
        )
        XCTAssertEqual(
            try harness.factory.currentGenerationPointerV3(
                expectedGenerationID: oldID,
                authority: coldAuthority
            ),
            expectedCurrentPointer
        )
        try harness.factory.requireInstalledRestoreGenerationSnapshot(
            expectedOldID: oldID,
            generationID: newID,
            expectedManifestDigest: manifestDigest,
            restoreProof: proof,
            restoreFileSnapshot: installedSnapshot,
            authority: coldAuthority
        )
        try harness.factory.removePreparedRestoreGenerationManifestBeforeDiscard(
            expectedOldID: oldID,
            generationID: newID,
            expectedDigest: manifestDigest,
            restoreProof: proof,
            restoreFileSnapshot: installedSnapshot,
            authority: coldAuthority
        )
        try harness.factory.removeInstalledGeneration(
            id: newID,
            keeping: oldID,
            authority: coldAuthority
        )
        let presence = try harness.factory.generationPresence(
            id: newID,
            authority: coldAuthority
        )
        XCTAssertFalse(presence.staging)
        XCTAssertFalse(presence.installed)
        try assertRestorePointerPublicationScope()
    }

    @MainActor
    func assertRestorePointerPublicationScope() throws {
        for scenario in ["no-call", "before-throw", "caught-denial", "cas-failure", "repeated", "after-throw", "success"] {
            let harness = try makeHarness("pointer-scope-\(scenario)")
            defer { try? fileManager.removeItem(at: harness.root) }
            let authority = try harness.factory.makeRestoreGenerationAuthority()
            let oldID = harness.session.generationID, newID = UUID()
            try harness.factory.createRestoreStagingGeneration(id: newID, authority: authority,
                recordsSchemaVersion: C05EvidenceCurationMigrationBoundaryV1.currentRecordsSchemaVersion,
                sourceGenerationID: oldID, archiveProvenanceSHA256: String(repeating: "b", count: 64),
                populate: { _ in })
            let digest = try harness.factory.prepareRestoreStagingGenerationManifest(
                expectedOldID: oldID, newID: newID, authority: authority)
            try harness.factory.installRestoreStagingGeneration(id: newID, authority: authority)
            let pointer = try harness.factory.currentGenerationPointerV3(
                expectedGenerationID: oldID, authority: authority)
            let staging = try DraftAttachmentStagingAdapterV1(applicationSupportURL: harness.support,
                workspaceID: harness.session.workspaceID)
            let proof = try staging.prepareEmptyPhotoBackupVerification()
            var checked = 0, scopeEntered = false, heldThroughPointer = false
            do {
                try harness.factory.switchCurrentGeneration(expected: oldID, to: newID,
                    expectedCurrentPointer: pointer, identity: harness.session.workspaceIdentity,
                    knownReplicaIDs: [harness.session.replicaID],
                    preparedGenerationManifestSHA256: digest, authority: authority,
                    publicationValidation: {
                        checked += 1
                        // A second legitimate acquisition cannot enter this root
                        // before or after the actual factory-owned pointer CAS.
                        XCTAssertThrowsError(try staging.prepareEmptyPhotoBackupVerification())
                        if scenario == "caught-denial" { throw FixtureError.publicationDenied }
                    }, publicationScope: { publishPointer in
                        scopeEntered = true
                        if scenario == "no-call" { return }
                        if scenario == "before-throw" { throw FixtureError.publicationDenied }
                        try proof.withVerificationLock {
                            if scenario == "cas-failure" {
                                let pointerURL = harness.support
                                    .appendingPathComponent("FieldEvidenceData/current.json")
                                let original = try Data(contentsOf: pointerURL)
                                var object = try XCTUnwrap(
                                    JSONSerialization.jsonObject(with: original)
                                        as? [String: Any]
                                )
                                var replicas = try XCTUnwrap(
                                    object["knownReplicaIDs"] as? [String]
                                )
                                replicas.append(UUID().uuidString.lowercased())
                                object["knownReplicaIDs"] = replicas.sorted()
                                let competing = try JSONSerialization.data(
                                    withJSONObject: object,
                                    options: [.sortedKeys, .withoutEscapingSlashes]
                                )
                                try competing.write(to: pointerURL, options: .atomic)
                                try ProtectedFilePolicyV1.applyAndVerify(
                                    .generationPointer,
                                    at: pointerURL
                                )
                                defer {
                                    try? original.write(to: pointerURL, options: .atomic)
                                    try? ProtectedFilePolicyV1.applyAndVerify(
                                        .generationPointer,
                                        at: pointerURL
                                    )
                                }
                                try publishPointer()
                                return
                            }
                            if scenario == "caught-denial" {
                                do { try publishPointer() } catch { }
                            } else { try publishPointer() }
                            if scenario == "repeated" {
                                do { try publishPointer() } catch { }
                            }
                            XCTAssertThrowsError(try staging.prepareEmptyPhotoBackupVerification())
                            heldThroughPointer = true
                            if scenario == "after-throw" { throw FixtureError.publicationDenied }
                        }
                    })
                XCTAssertEqual(scenario, "success", "A swallowed or omitted CAS must not report success")
            } catch {
                XCTAssertNotEqual(scenario, "success")
            }
            XCTAssertTrue(scopeEntered)
            XCTAssertEqual(checked, scenario == "no-call" || scenario == "before-throw" ? 0 : 1)
            XCTAssertEqual(
                heldThroughPointer,
                !["no-call", "before-throw", "cas-failure"].contains(scenario)
            )
            let published = ["repeated", "after-throw", "success"].contains(scenario)
            XCTAssertEqual(try harness.factory.currentGenerationID(authority: authority), published ? newID : oldID)
            if !published {
                XCTAssertEqual(try harness.factory.currentGenerationPointerV3(
                    expectedGenerationID: oldID, authority: authority), pointer)
            }
            _ = try staging.prepareEmptyPhotoBackupVerification()
        }
    }

    @MainActor
    func makeSourcePackage(
        in root: URL,
        name: String,
        siteAddress: String? = nil,
        seed: ((StoreGenerationSession) throws -> Void)? = nil
    ) throws -> URL {
        let support = root.appendingPathComponent(
            "\(name)-support",
            isDirectory: true
        )
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let session = try StoreGenerationFactory(
            applicationSupportURL: support
        ).openOrBootstrapCurrent()
        let siteID = uuid("64000000-0000-0000-0000-000000000001")
        session.modelContext.insert(Site(
            id: siteID,
            label: "North lot",
            address: siteAddress,
            timeZoneID: "America/New_York",
            createdAt: Date(timeIntervalSince1970: 1_786_708_800)
        ))
        session.modelContext.insert(Asset(
            id: uuid("64000000-0000-0000-0000-000000000002"),
            siteID: siteID,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Pylon sign",
            createdAt: Date(timeIntervalSince1970: 1_786_708_801)
        ))
        try seed?(session)
        try session.modelContext.save()
        let destination = root.appendingPathComponent(
            "\(name)-export",
            isDirectory: true
        )
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_786_708_900) }
        )
        let preview = try exporter.prepare()
        return try exporter.export(previewID: preview.id, to: destination)
    }

    @MainActor
    func importPackage(
        _ package: URL,
        into session: StoreGenerationSession
    ) throws -> ValidatedV4BackupPackageV1 {
        try BackupImportService(
            generationRootURL: session.generationRootURL,
            makeUUID: { self.uuid("64000000-0000-0000-0000-000000000099") },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return {
            guard !remaining.isEmpty else { return UUID() }
            return remaining.removeFirst()
        }
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    func accessibleFixturePNG(seed: UInt8) throws -> Data {
        let width = 48, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = seed &+ UInt8(truncatingIfNeeded: index / 4)
            pixels[index + 1] = seed &+ 17
            pixels[index + 2] = seed &+ 43
            pixels[index + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw FixtureError.invalid
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw FixtureError.invalid
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.invalid
        }
        return output as Data
    }

    func tree(_ root: URL) throws -> [FileFact] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw FixtureError.invalid }
        var facts: [FileFact] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let relative = String(
                url.standardizedFileURL.path.dropFirst(
                    root.standardizedFileURL.path.count + 1
                )
            )
            facts.append(FileFact(path: relative, bytes: try Data(contentsOf: url)))
        }
        return facts.sorted { $0.path < $1.path }
    }

    struct AccessibleDocumentPackageFixture {
        let package: URL
        let tree: AccessibleDocumentSemanticTreeV1
    }

    @MainActor
    func makeAccessibleDocumentPackage(in root: URL) async throws -> AccessibleDocumentPackageFixture {
        let support = root.appendingPathComponent("accessible-document-source", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        var writerReleased = false
        defer {
            if !writerReleased {
                try? coordinator.invalidateAndReleaseWriter()
            }
        }

        let pack = SignPack.illuminatedSignV1
        let siteID = uuid("64000000-0000-0000-0000-000000000701")
        let assetID = uuid("64000000-0000-0000-0000-000000000702")
        let placementMutationID = try MutationIDV1(rawValue: uuid("64000000-0000-0000-0000-000000000703"))
        _ = try coordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID,
            newSite: .init(id: siteID, label: "Accessible restore site", address: nil, timeZoneID: "America/New_York"),
            assetID: assetID, assetLabel: "Accessible restore sign", packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            initialPlacementMutationID: placementMutationID,
            initialPlacementEventID: uuid("64000000-0000-0000-0000-000000000704"),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: uuid("64000000-0000-0000-0000-000000000705"))
        )), mutationID: placementMutationID)
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let dependencies = try coordinator.packageLifecycleDependencies(
            profileRegistry: WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        )
        let runner = try CheckRunnerCoordinator(
            modelContext: session.modelContext,
            packageLifecycleDependencies: dependencies,
            packageLifecycleProfile: profile
        )
        runner.configureCapture(generationRootURL: session.generationRootURL)
        let observedAt = Date(timeIntervalSince1970: 1_800_000_100)
        _ = try runner.beginCheck(
            assetID: assetID, timeZoneID: nil, isTimeZoneConfirmed: false,
            afterDarkAccepted: true, safePositionAccepted: true, observedAt: observedAt
        )
        let wide = try await runner.importCandidate(
            assetID: assetID, sourceData: try accessibleFixturePNG(seed: 31),
            createdAt: observedAt.addingTimeInterval(1)
        )
        _ = try await runner.accept(candidate: wide, assetID: assetID)
        let close = try await runner.importCandidate(
            assetID: assetID, sourceData: try accessibleFixturePNG(seed: 71),
            createdAt: observedAt.addingTimeInterval(2)
        )
        _ = try await runner.accept(candidate: close, assetID: assetID)
        let reportID = uuid("64000000-0000-0000-0000-000000000706")
        let result = try await runner.finalize(
            assetID: assetID, selection: .noVisibleIssue,
            completedAt: observedAt.addingTimeInterval(5),
            snapshotCreatedAt: observedAt.addingTimeInterval(6),
            sourceApp: .init(build: "42", version: "4.0"),
            identifiers: .init(
                mutationID: uuid("64000000-0000-0000-0000-000000000707"),
                packetID: uuid("64000000-0000-0000-0000-000000000708"),
                stableRootID: uuid("64000000-0000-0000-0000-000000000709"),
                reportID: reportID, issueID: nil
            )
        )
        guard case .ready = try runner.prepareReportDelivery(result: result) else {
            throw FixtureError.invalid
        }
        let report = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<Report>()).first { $0.id == reportID })
        let snapshotRelativePath = report.snapshotRelativePath
        let pdfRelativePath = try XCTUnwrap(report.pdfRelativePath)
        let snapshotSHA256 = report.snapshotSHA256
        let pdfSHA256 = try XCTUnwrap(report.pdfSHA256)
        let snapshotBytes = try Data(contentsOf: session.generationRootURL.appendingPathComponent(snapshotRelativePath))
        let pdfBytes = try Data(contentsOf: session.generationRootURL.appendingPathComponent(pdfRelativePath))
        guard KernelCanonicalHashV1.sha256(snapshotBytes) == snapshotSHA256,
              KernelCanonicalHashV1.sha256(pdfBytes) == pdfSHA256,
              !pdfBytes.isEmpty else {
            throw FixtureError.invalid
        }
        let publication = try AccessibleDocumentPublicationBindingV1(
            snapshotSHA256: snapshotSHA256, manifestID: "s64.restore.manifest", manifestVersion: 1,
            manifestSHA256: snapshotSHA256, localeIdentifier: "en-US", profileID: "s64.restore.profile",
            profileRelease: 1, profileSHA256: snapshotSHA256, brandProfileID: "s64.restore.brand",
            brandProfileRelease: 1, brandProfileSHA256: snapshotSHA256
        )
        let tree = try AccessibleDocumentSemanticTreeResolverV1.rebuild(.init(
            workspaceID: session.workspaceIdentity.workspaceID, audience: .internalUse,
            publication: publication,
            nodes: [try AccessibleDocumentNodeV1(
                nodeID: "restore-document", role: .document, parentNodeID: nil, order: 0,
                localizedText: "Accessible restore report", sensitivity: .customerSafe
            )],
            projectionVersion: "s64.restore.access"
        ))
        let reviewer = try ActorSnapshotV1(
            snapshotID: uuid("64000000-0000-0000-0000-000000000710"),
            workspaceID: session.workspaceIdentity.workspaceID,
            actor: LocalActorReferenceV1(
                actorReferenceID: uuid("64000000-0000-0000-0000-000000000711"),
                workspaceID: session.workspaceIdentity.workspaceID,
                displayName: "Accessible restore reviewer"
            ),
            responsibility: .reviewedBy, displayNameAtTime: "Accessible restore reviewer",
            capturedAt: observedAt.addingTimeInterval(7)
        )
        let assessment = try AccessibleDocumentAssessmentReceiptV1(
            receiptID: uuid("64000000-0000-0000-0000-000000000712"),
            workspaceID: session.workspaceIdentity.workspaceID, tree: tree,
            outputSHA256: pdfSHA256, outputByteCount: Int64(pdfBytes.count),
            outputMediaType: "application/pdf", rendererID: "existing-report-renderer",
            rendererVersion: "1", assessmentToolID: "s64.restore.assessor", assessmentToolVersion: "1",
            assessor: reviewer, state: .internalPass, limitations: ["Local restore fixture"],
            assessedAt: observedAt.addingTimeInterval(8),
            mutationID: try MutationIDV1(rawValue: uuid("64000000-0000-0000-0000-000000000713"))
        )
        try assessment.validate(tree: tree)
        _ = try coordinator.workspaceWriter.commitAccessibleDocumentAssessment(
            AccessibleDocumentMutationV1(receipt: assessment), validatedAgainst: tree
        )
        try coordinator.invalidateAndReleaseWriter()
        writerReleased = true
        let journal = try MutationJournalStoreV1(
            modelContext: session.modelContext, identity: session.workspaceIdentity,
            generationID: session.generationID, allowStateBootstrap: false
        )
        try journal.validateAll()
        let exportRoot = root.appendingPathComponent("accessible-document-export", isDirectory: true)
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: session.modelContext, generationRootURL: session.generationRootURL
        )
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: exportRoot)
        return AccessibleDocumentPackageFixture(package: package, tree: tree)
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C41AtomicRestoreRebindsDescriptorAndEventTogether() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_640)
        let snapshot = try CompletedFunctionalRelationshipSnapshotV1(
            snapshotID: C41FunctionalRelationshipTestSupportV1.id(41_642),
            workspaceID: fixture.workspaceID,
            capturedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
            descriptorReleases: [fixture.descriptor],
            relationships: [fixture.added]
        )
        let restoredWorkspace = C41FunctionalRelationshipTestSupportV1.workspace(41_643)
        let restored = try snapshot.rebound(to: restoredWorkspace)

        XCTAssertEqual(restored.workspaceID, restoredWorkspace)
        XCTAssertEqual(restored.descriptorReleases.first?.workspaceID, restoredWorkspace)
        XCTAssertEqual(restored.relationships.first?.workspaceID, restoredWorkspace)
        XCTAssertEqual(restored.relationships.first?.actor.workspaceID, restoredWorkspace)
        XCTAssertNotEqual(restored.snapshotSHA256, snapshot.snapshotSHA256)
        try restored.validate()
    }
}

private extension S6_4AtomicRestoreTests {
    @MainActor
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        verify: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            verify(error)
        }
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C14AtomicRestoreRoundTripsAllFivePersistentRows() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_164)
        let transitionRow = try InspectionReviewTransitionRow(fixture.transitions[0])
        let dispositionRow = try ReviewDispositionRow(fixture.acceptedDisposition)
        let requestRow = try ChangeRequestRow(fixture.resolvedChangeRequest)
        let policyRow = try CorrectiveActionPolicyRow(fixture.policy)
        let eventRow = try CorrectiveActionEventRow(fixture.actions[3])
        XCTAssertEqual(try transitionRow.value(), fixture.transitions[0])
        XCTAssertEqual(try dispositionRow.value(), fixture.acceptedDisposition)
        XCTAssertEqual(try requestRow.value(), fixture.resolvedChangeRequest)
        XCTAssertEqual(try policyRow.value(), fixture.policy)
        XCTAssertEqual(try eventRow.value(), fixture.actions[3])
    }

    func testV23P03C19RestoreRehydratesImmutableCaptureAndCalibrationRows() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let captureRow = try MeasurementCaptureRow(fixture.capture)
        let calibrationRow = try CalibrationStatusSnapshotRow(fixture.currentCalibration)
        XCTAssertEqual(try captureRow.value(), fixture.capture)
        XCTAssertEqual(try calibrationRow.value(), fixture.currentCalibration)
        XCTAssertEqual(captureRow.mutationID, calibrationRow.mutationID)
        XCTAssertEqual(captureRow.workspaceID, calibrationRow.workspaceID)
    }

    func testC20PrivacyTransformRestoreAcceptsOnlyCompletePublicationReceipt() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let receipt = try PrivacyTransformPublicationReceiptV1(
            bundle: fixture.bundle,
            canonicalMutationReceiptSHA256: C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        try receipt.validate(
            bundle: fixture.bundle,
            expectedCanonicalMutationReceiptSHA256:
                C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        XCTAssertEqual(receipt.manifestID, fixture.manifest.manifestID)
        XCTAssertThrowsError(try fixture.original.validatePrivacyDerivative(fixture.original))
    }
}

extension S6_4AtomicRestoreTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension S6_4AtomicRestoreTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies.count, 2)
        XCTAssertEqual(PersistentSchemaV24.models.count, 87)
    }
}
extension S6_4AtomicRestoreTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS64AtomicRestoreTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testC32SeededAcceptanceFixtureRejectsLaterDirectMutationWithoutCheckpointAdoption() throws {
        let harness = try makeHarness("c32-seeded-checkpoint-drift")
        addTeardownBlock { [root = harness.root] in
            try? FileManager.default.removeItem(at: root)
        }
        _ = try C32AssistanceTestSupport.commitPersistentAcceptance(
            in: harness.session,
            slot: 619
        )
        let context = harness.session.modelContext
        context.insert(Site(
            id: uuid("64000000-0000-0000-0000-000000000619"),
            label: "Unadopted C32 fixture site",
            address: nil,
            timeZoneID: "UTC",
            createdAt: Date(timeIntervalSince1970: 1_786_708_619)
        ))
        try context.save()

        let journal = try MutationJournalStoreV1(
            modelContext: context,
            identity: harness.session.workspaceIdentity,
            generationID: harness.session.generationID,
            allowStateBootstrap: false
        )
        XCTAssertThrowsError(try journal.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
    }

    @MainActor
    func testC32RealBackupRestorePreservesImmutableAcceptanceAndRebindsOnlyTargetFacts() async throws {
        for (offset, mode) in [
            BackupRestoreMode.emptyInstall,
            .replaceExisting,
            .clone,
            .fork
        ].enumerated() {
            let harness = try makeHarness("c32-real-restore-\(offset)")
            addTeardownBlock { [root = harness.root] in
                try? FileManager.default.removeItem(at: root)
            }
            var sourceReceipt: AssistanceAcceptanceReceiptV1?
            var sourceAcceptanceBytes: Data?
            var sourceEnvelopeBytes: Data?
            var sourceMutationReceiptBytes: Data?
            let package = try makeSourcePackage(
                in: harness.root,
                name: "c32-source-\(offset)",
                seed: { sourceSession in
                    let receipt = try C32AssistanceTestSupport.commitPersistentAcceptance(
                        in: sourceSession,
                        slot: 620 + offset
                    )
                    sourceReceipt = receipt
                    sourceAcceptanceBytes = try XCTUnwrap(
                        sourceSession.modelContext.fetch(
                            FetchDescriptor<AssistanceAcceptanceReceiptRow>()
                        ).first
                    ).canonicalData
                    let mutationRow = try XCTUnwrap(
                        sourceSession.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                            .first { $0.mutationID == receipt.mutationID.rawValue }
                    )
                    sourceEnvelopeBytes = mutationRow.envelopeData
                    sourceMutationReceiptBytes = mutationRow.receiptData
                }
            )
            let expectedReceipt = try XCTUnwrap(sourceReceipt)
            let expectedAcceptanceBytes = try XCTUnwrap(sourceAcceptanceBytes)
            let expectedEnvelopeBytes = try XCTUnwrap(sourceEnvelopeBytes)
            let expectedMutationReceiptBytes = try XCTUnwrap(sourceMutationReceiptBytes)
            let validated = try importPackage(package, into: harness.session)
            XCTAssertEqual(validated.records.assistanceAcceptanceReceipts.count, 1)
            XCTAssertEqual(validated.records.mutationHistory?.receipts.count, 1)
            let restored = try await BackupRestoreService(
                applicationSupportURL: harness.support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL,
                mode: mode
            )
            let acceptanceRows = try restored.modelContext.fetch(
                FetchDescriptor<AssistanceAcceptanceReceiptRow>()
            )
            XCTAssertEqual(acceptanceRows.count, 1)
            let restoredReceipt = try XCTUnwrap(acceptanceRows.first).value()
            XCTAssertEqual(restoredReceipt, expectedReceipt)
            XCTAssertEqual(acceptanceRows[0].canonicalData, expectedAcceptanceBytes)
            XCTAssertEqual(restoredReceipt.receiptSHA256, expectedReceipt.receiptSHA256)
            XCTAssertEqual(restoredReceipt.workspaceID, expectedReceipt.workspaceID)

            let mutationRow = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                    .first { $0.mutationID == expectedReceipt.mutationID.rawValue }
            )
            XCTAssertEqual(mutationRow.envelopeData, expectedEnvelopeBytes)
            XCTAssertEqual(mutationRow.receiptData, expectedMutationReceiptBytes)

            let restoredFact = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<FactCaptureRow>()).first
            ).value()
            XCTAssertEqual(restoredFact.value, expectedReceipt.acceptedValue)
            XCTAssertEqual(restoredFact.workspaceID, restored.workspaceID)

            let restoredJournal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID,
                allowStateBootstrap: false
            )
            try restoredJournal.validateAll()
            if mode == .clone || mode == .fork {
                XCTAssertNotEqual(restored.workspaceID, expectedReceipt.workspaceID)
                XCTAssertNil(try restoredJournal.assistanceAcceptanceReceipt(
                    mutationID: expectedReceipt.mutationID
                ))
            } else {
                XCTAssertEqual(restored.workspaceID, expectedReceipt.workspaceID)
                XCTAssertEqual(
                    try restoredJournal.assistanceAcceptanceReceipt(
                        mutationID: expectedReceipt.mutationID
                    ),
                    expectedReceipt
                )
            }
            XCTAssertFalse(AssistancePersistenceEnrollmentV1.proposalIsPersistent)
            XCTAssertFalse(AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent)
        }

        let chainHarness = try makeHarness("c32-historic-chain")
        addTeardownBlock { [root = chainHarness.root] in
            try? FileManager.default.removeItem(at: root)
        }
        var originalReceipt: AssistanceAcceptanceReceiptV1?
        var originalAcceptanceBytes: Data?
        var originalEnvelopeBytes: Data?
        var originalMutationReceiptBytes: Data?
        let sourcePackage = try makeSourcePackage(
            in: chainHarness.root,
            name: "c32-historic-source",
            seed: { sourceSession in
                let receipt = try C32AssistanceTestSupport.commitPersistentAcceptance(
                    in: sourceSession,
                    slot: 630
                )
                originalReceipt = receipt
                originalAcceptanceBytes = try XCTUnwrap(
                    sourceSession.modelContext.fetch(
                        FetchDescriptor<AssistanceAcceptanceReceiptRow>()
                    ).first
                ).canonicalData
                let mutationRow = try XCTUnwrap(
                    sourceSession.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                        .first { $0.mutationID == receipt.mutationID.rawValue }
                )
                originalEnvelopeBytes = mutationRow.envelopeData
                originalMutationReceiptBytes = mutationRow.receiptData
            }
        )
        let expectedReceipt = try XCTUnwrap(originalReceipt)
        let expectedAcceptanceBytes = try XCTUnwrap(originalAcceptanceBytes)
        let expectedEnvelopeBytes = try XCTUnwrap(originalEnvelopeBytes)
        let expectedMutationReceiptBytes = try XCTUnwrap(originalMutationReceiptBytes)

        func assertHistoricSourceProvenance(
            in session: StoreGenerationSession,
            expectedCurrentWorkspaceID: WorkspaceID? = nil
        ) throws {
            let acceptanceRows = try session.modelContext.fetch(
                FetchDescriptor<AssistanceAcceptanceReceiptRow>()
            )
            XCTAssertEqual(acceptanceRows.count, 1)
            let receipt = try XCTUnwrap(acceptanceRows.first).value()
            XCTAssertEqual(receipt, expectedReceipt)
            XCTAssertEqual(acceptanceRows[0].canonicalData, expectedAcceptanceBytes)
            XCTAssertEqual(receipt.receiptSHA256, expectedReceipt.receiptSHA256)
            XCTAssertEqual(receipt.workspaceID, expectedReceipt.workspaceID)
            XCTAssertNotEqual(session.workspaceID, expectedReceipt.workspaceID)
            if let expectedCurrentWorkspaceID {
                XCTAssertEqual(session.workspaceID, expectedCurrentWorkspaceID)
            }

            let mutationRow = try XCTUnwrap(
                session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                    .first { $0.mutationID == expectedReceipt.mutationID.rawValue }
            )
            XCTAssertEqual(mutationRow.envelopeData, expectedEnvelopeBytes)
            XCTAssertEqual(mutationRow.receiptData, expectedMutationReceiptBytes)

            let fact = try XCTUnwrap(
                session.modelContext.fetch(FetchDescriptor<FactCaptureRow>()).first
            ).value()
            XCTAssertEqual(fact.value, expectedReceipt.acceptedValue)
            XCTAssertEqual(fact.workspaceID, session.workspaceID)

            let journal = try MutationJournalStoreV1(
                modelContext: session.modelContext,
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                allowStateBootstrap: false
            )
            try journal.validateAll()
            XCTAssertNil(try journal.assistanceAcceptanceReceipt(
                mutationID: expectedReceipt.mutationID
            ))
        }

        let cloned = try await BackupRestoreService(
            applicationSupportURL: chainHarness.support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: try importPackage(sourcePackage, into: chainHarness.session),
            currentModelContext: chainHarness.session.modelContext,
            currentGenerationID: chainHarness.session.generationID,
            currentGenerationRootURL: chainHarness.session.generationRootURL,
            mode: .clone
        )
        try assertHistoricSourceProvenance(in: cloned)

        let cloneExportDirectory = chainHarness.root.appendingPathComponent(
            "c32-historic-clone-export",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: cloneExportDirectory,
            withIntermediateDirectories: true
        )
        let cloneExporter = BackupExportService(
            modelContext: cloned.modelContext,
            generationRootURL: cloned.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_786_709_000) }
        )
        let clonePreview = try cloneExporter.prepare()
        let clonePackage = try cloneExporter.export(
            previewID: clonePreview.id,
            to: cloneExportDirectory
        )

        let forked = try await BackupRestoreService(
            applicationSupportURL: chainHarness.support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: try importPackage(clonePackage, into: cloned),
            currentModelContext: cloned.modelContext,
            currentGenerationID: cloned.generationID,
            currentGenerationRootURL: cloned.generationRootURL,
            mode: .fork
        )
        XCTAssertNotEqual(forked.workspaceID, cloned.workspaceID)
        try assertHistoricSourceProvenance(in: forked)

        let forkExportDirectory = chainHarness.root.appendingPathComponent(
            "c32-historic-fork-export",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: forkExportDirectory,
            withIntermediateDirectories: true
        )
        let forkExporter = BackupExportService(
            modelContext: forked.modelContext,
            generationRootURL: forked.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_786_709_100) }
        )
        let forkPreview = try forkExporter.prepare()
        let forkPackage = try forkExporter.export(
            previewID: forkPreview.id,
            to: forkExportDirectory
        )

        let ordinaryHarness = try makeHarness("c32-historic-chain-empty-install")
        addTeardownBlock { [root = ordinaryHarness.root] in
            try? FileManager.default.removeItem(at: root)
        }
        let ordinaryRestored = try await BackupRestoreService(
            applicationSupportURL: ordinaryHarness.support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: try importPackage(forkPackage, into: ordinaryHarness.session),
            currentModelContext: ordinaryHarness.session.modelContext,
            currentGenerationID: ordinaryHarness.session.generationID,
            currentGenerationRootURL: ordinaryHarness.session.generationRootURL,
            mode: .emptyInstall
        )
        try assertHistoricSourceProvenance(
            in: ordinaryRestored,
            expectedCurrentWorkspaceID: forked.workspaceID
        )
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C34SceneRestoreThenEraseLeavesNoState() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x0a)))
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .work)
        let today = try NavigationTargetV1(workspaceID: workspace, destination: .today)
        let assets = try NavigationTargetV1(workspaceID: workspace, destination: .assets)
        let reports = try NavigationTargetV1(workspaceID: workspace, destination: .reports)
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .work, paths: [
            .init(root: .today, targets: [today]),
            .init(root: .work, targets: [target]),
            .init(root: .assets, targets: [assets]),
            .init(root: .reports, targets: [reports])
        ], snapshotID: UUID())
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        try adapter.save(snapshot)
        XCTAssertEqual(try adapter.loadAndReconcile(), .restored(snapshot))
        try adapter.erase()
        XCTAssertEqual(try adapter.loadAndReconcile(), .absent)
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testC33RealBackupRestoreCloneForkCarryDirectOriginalBytesAndTypedRows() async throws {
        let sourceRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "c33-real-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: sourceRoot) }
        let sourceSupport = sourceRoot.appendingPathComponent("Application Support", isDirectory: true)
        try fileManager.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let sourceSession = try StoreGenerationFactory(
            applicationSupportURL: sourceSupport
        ).openOrBootstrapCurrent()
        let source = try await C33TemporalEvidenceTestSupport.commitPersistentClip(
            in: sourceSession,
            slot: 730
        )
        let sourceAnchors = try C33TemporalEvidenceTestSupport.commitPersistentAnchors(
            in: sourceSession,
            clip: source.clip,
            slots: [731, 732, 733]
        )
        let sourceSnapshots = try C33TemporalEvidenceTestSupport.persistReportSnapshots(
            in: sourceSession,
            clip: source.clip,
            anchorSubsets: [
                [sourceAnchors[0], sourceAnchors[1]],
                [sourceAnchors[1], sourceAnchors[2]]
            ],
            slot: 740
        )
        try sourceSession.modelContext.save()
        let sourceSnapshotsByID = Dictionary(
            uniqueKeysWithValues: sourceSnapshots.map { ($0.reportID, $0) }
        )
        let sourceSnapshotSHAByID = try Dictionary(uniqueKeysWithValues: sourceSnapshots.map {
            ($0.reportID, try ReportSnapshotEncoderV1().encode($0).sha256)
        })
        let sourceRow = try XCTUnwrap(
            sourceSession.modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).first
        )
        let sourceCanonicalData = sourceRow.canonicalData
        let sourceOriginalDigest = try XCTUnwrap(
            source.clip.original.digests.digest(for: .sha256)
        )
        let sourceBytes = C33TemporalEvidenceTestSupport.bytes(for: source.clip.facts.kind)
        let exportDirectory = sourceRoot.appendingPathComponent("Export", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: sourceSession.modelContext,
            generationRootURL: sourceSession.generationRootURL,
            now: { C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(100) }
        )
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: exportDirectory)

        for (offset, mode) in [
            BackupRestoreMode.emptyInstall,
            .clone,
            .fork
        ].enumerated() {
            let harness = try makeHarness("c33-real-restore-\(offset)")
            defer { try? fileManager.removeItem(at: harness.root) }
            let validated = try importPackage(package, into: harness.session)
            XCTAssertEqual(validated.manifest.source.persistentSchemaVersion, 33)
            XCTAssertEqual(validated.records.recordsSchemaVersion, 32)
            XCTAssertEqual(validated.records.temporalEvidence.count, 1)
            XCTAssertEqual(validated.records.reports.count, 2)
            let archived = try XCTUnwrap(validated.records.temporalEvidence.first).clipValue()
            XCTAssertEqual(archived, source.clip)
            XCTAssertEqual(
                try XCTUnwrap(validated.records.temporalEvidence.first).canonicalData,
                sourceCanonicalData
            )
            let sourceMember = try TemporalEvidenceBackupMemberV1.original(for: source.clip)
            XCTAssertEqual(validated.members[sourceMember], sourceBytes)

            if offset == 0 {
                let profile = try C33TemporalEvidenceTestSupport.profile(
                    workspaceID: source.clip.workspaceID,
                    reportProjection: .typedLinkOnly
                )
                let conflictingClip = try TemporalEvidenceClipV1(
                    clipID: source.clip.clipID,
                    workspaceID: source.clip.workspaceID,
                    target: source.clip.target,
                    original: source.clip.original,
                    originalProvenance: source.clip.originalProvenance,
                    locator: source.clip.locator,
                    facts: source.clip.facts,
                    profile: profile,
                    accessibleDescription: source.clip.accessibleDescription + " Conflicting envelope.",
                    manualTranscript: source.clip.manualTranscript,
                    recordedBy: source.clip.recordedBy,
                    capturedAt: source.clip.capturedAt,
                    acceptedAt: source.clip.acceptedAt,
                    supersedesClipID: source.clip.supersedesClipID,
                    revision: source.clip.revision,
                    mutationID: source.clip.mutationID
                )
                var recordsObject = try XCTUnwrap(
                    JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(validated.records)
                    ) as? [String: Any]
                )
                recordsObject["temporalEvidence"] = try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode([
                        try V33BackupTemporalEvidenceRecordV1(conflictingClip)
                    ])
                )
                let conflictingRecords = try JSONDecoder().decode(
                    V4BackupRecordsV1.self,
                    from: JSONSerialization.data(withJSONObject: recordsObject)
                )
                XCTAssertThrowsError(try conflictingRecords.validateC33TemporalEvidence())
                let conflictingPackage = ValidatedV4BackupPackageV1(
                    stagedPackageURL: validated.stagedPackageURL,
                    manifest: validated.manifest,
                    records: conflictingRecords,
                    members: validated.members,
                    summary: validated.summary
                )
                do {
                    _ = try await BackupRestoreService(
                        applicationSupportURL: harness.support,
                        storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
                    ).restore(
                        validatedPackage: conflictingPackage,
                        currentModelContext: harness.session.modelContext,
                        currentGenerationID: harness.session.generationID,
                        currentGenerationRootURL: harness.session.generationRootURL,
                        mode: .emptyInstall
                    )
                    XCTFail("mismatched temporal record/envelope pair restored")
                } catch { }
                XCTAssertEqual(
                    try harness.session.modelContext.fetchCount(
                        FetchDescriptor<TemporalEvidenceClipRow>()
                    ),
                    0
                )
            }

            let restored = try await BackupRestoreService(
                applicationSupportURL: harness.support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL,
                mode: mode
            )
            let rows = try restored.modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>())
            XCTAssertEqual(rows.count, 1)
            let clip = try XCTUnwrap(rows.first).value()
            let restoredAnchors = try restored.modelContext.fetch(
                FetchDescriptor<TimecodedEvidenceAnchorRow>()
            ).map { try $0.value() }
            XCTAssertEqual(restoredAnchors.count, 3)
            XCTAssertEqual(clip.workspaceID, restored.workspaceID)
            XCTAssertEqual(clip.original.contentID, source.clip.original.contentID)
            XCTAssertEqual(clip.original.digests.digest(for: .sha256), sourceOriginalDigest)
            XCTAssertEqual(clip.facts, source.clip.facts)
            XCTAssertEqual(
                try Data(contentsOf: restored.generationRootURL.appendingPathComponent(
                    try TemporalEvidenceBackupMemberV1.original(for: clip)
                )),
                sourceBytes
            )
            if mode == .emptyInstall || mode == .replaceExisting {
                XCTAssertEqual(clip.workspaceID, source.clip.workspaceID)
                XCTAssertEqual(rows[0].canonicalData, sourceCanonicalData)
                XCTAssertEqual(clip.limitProfile, source.clip.limitProfile)
            } else {
                XCTAssertNotEqual(clip.workspaceID, source.clip.workspaceID)
                XCTAssertNotEqual(rows[0].canonicalData, sourceCanonicalData)
                XCTAssertEqual(clip.limitProfile.profileID, source.clip.limitProfile.profileID)
                XCTAssertEqual(
                    clip.limitProfile.revision,
                    source.clip.limitProfile.revision + 1
                )
                XCTAssertEqual(clip.limitProfile.audio, source.clip.limitProfile.audio)
                XCTAssertEqual(clip.limitProfile.video, source.clip.limitProfile.video)
                XCTAssertEqual(
                    clip.limitProfile.maximumClipsPerRequirement,
                    source.clip.limitProfile.maximumClipsPerRequirement
                )
                XCTAssertEqual(
                    clip.limitProfile.maximumClipsPerSession,
                    source.clip.limitProfile.maximumClipsPerSession
                )
                XCTAssertEqual(
                    clip.limitProfile.minimumFreeByteCount,
                    source.clip.limitProfile.minimumFreeByteCount
                )
                XCTAssertEqual(
                    clip.limitProfile.reportProjection,
                    source.clip.limitProfile.reportProjection
                )
                XCTAssertEqual(
                    clip.limitProfile.requiresAccessibleDescription,
                    source.clip.limitProfile.requiresAccessibleDescription
                )
                XCTAssertEqual(
                    clip.limitProfile.requiresManualTranscript,
                    source.clip.limitProfile.requiresManualTranscript
                )
                XCTAssertEqual(clip.limitProfile.definitionRelease, clip.target.definitionRelease)
                XCTAssertNotEqual(
                    clip.limitProfile.definitionRelease,
                    source.clip.limitProfile.definitionRelease
                )
                XCTAssertNotEqual(
                    clip.limitProfile.packageRelease,
                    source.clip.limitProfile.packageRelease
                )
                XCTAssertNotEqual(
                    clip.limitProfile.profileSHA256,
                    source.clip.limitProfile.profileSHA256
                )
                XCTAssertNotEqual(clip.clipSHA256, source.clip.clipSHA256)
            }
            let journal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID,
                allowStateBootstrap: false
            )
            try journal.validateAll()

            let reportRows = try restored.modelContext.fetch(FetchDescriptor<Report>(
                sortBy: [SortDescriptor(\.id)]
            ))
            XCTAssertEqual(reportRows.count, 2)
            var restoredSnapshots: [ReportSnapshotV1] = []
            for report in reportRows {
                let data = try Data(contentsOf: restored.generationRootURL.appendingPathComponent(
                    report.snapshotRelativePath
                ))
                XCTAssertEqual(KernelCanonicalHashV1.sha256(data), report.snapshotSHA256)
                let snapshot = try ReportSnapshotEncoderV1().decode(data)
                let sourceSnapshot = try XCTUnwrap(sourceSnapshotsByID[snapshot.reportID])
                let sourceLink = try XCTUnwrap(sourceSnapshot.temporalEvidenceLinks?.first)
                let link = try XCTUnwrap(snapshot.temporalEvidenceLinks?.first)
                XCTAssertEqual(link.workspaceID, clip.workspaceID)
                XCTAssertEqual(link.clipID, clip.clipID)
                XCTAssertEqual(link.clipRevision, clip.revision)
                XCTAssertEqual(link.clipSHA256, clip.clipSHA256)
                XCTAssertEqual(link.contentID, clip.original.contentID)
                XCTAssertEqual(link.contentID, sourceLink.contentID)
                XCTAssertEqual(link.accessibleDescription, sourceLink.accessibleDescription)
                XCTAssertEqual(link.manualTranscript, sourceLink.manualTranscript)
                let selectedDestinationAnchors = try sourceLink.anchorBindings.map { binding in
                    try XCTUnwrap(restoredAnchors.first(where: {
                        $0.anchorID == binding.anchorID && $0.revision == binding.revision
                    }))
                }
                let expectedBindings = try selectedDestinationAnchors.map {
                    try TemporalEvidenceReportAnchorBindingV1(anchor: $0, clip: clip)
                }.sorted()
                XCTAssertEqual(link.anchorBindings, expectedBindings)
                XCTAssertEqual(
                    link.anchorBindings.map {
                        "\($0.anchorID.uuidString.lowercased()):\($0.revision)"
                    },
                    sourceLink.anchorBindings.map {
                        "\($0.anchorID.uuidString.lowercased()):\($0.revision)"
                    }
                )
                try link.validate(clip: clip, anchors: selectedDestinationAnchors)
                XCTAssertEqual(snapshot.assurance == nil, sourceSnapshot.assurance == nil)
                if let assurance = snapshot.assurance {
                    XCTAssertEqual(assurance.preview.workspaceID, clip.workspaceID)
                    try assurance.validate()
                }
                if mode == .clone || mode == .fork {
                    XCTAssertNotEqual(
                        report.snapshotSHA256,
                        sourceSnapshotSHAByID[snapshot.reportID]
                    )
                }
                restoredSnapshots.append(snapshot)
            }
            let restoredLinks = restoredSnapshots.compactMap {
                $0.temporalEvidenceLinks?.first
            }
            XCTAssertEqual(restoredLinks.count, 2)
            XCTAssertEqual(restoredLinks[0].anchorCount, restoredLinks[1].anchorCount)
            XCTAssertNotEqual(
                Set(restoredLinks[0].anchorBindings.map(\.anchorID)),
                Set(restoredLinks[1].anchorBindings.map(\.anchorID))
            )

            if mode == .clone || mode == .fork {
                let boundRevision = try journal.currentRevision(
                    writerInstanceID: C33TemporalEvidenceTestSupport.id(9_900 + offset)
                )
                let recovery = try TemporalEvidencePromotionRecoveryFileAdapterV1(
                    generationRootURL: restored.generationRootURL,
                    workspaceID: clip.workspaceID,
                    verify: { _, _, _ in false },
                    remove: { _, _, _ in }
                )
                let deletionReferences = try await TemporalEvidenceDeletionExternalReferenceResolverV1(
                    modelContext: restored.modelContext,
                    generationRootURL: restored.generationRootURL,
                    journal: journal,
                    recovery: recovery
                ).temporalEvidenceReferences(
                    workspaceID: clip.workspaceID,
                    boundRevision: boundRevision
                )
                XCTAssertEqual(
                    deletionReferences.reportLinks,
                    restoredSnapshots.flatMap { $0.temporalEvidenceLinks ?? [] }
                )
            }
        }
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testV23P03C42AtomicRestorePublishesACompleteTypedReceipt() async throws {
        let receipts = [
            try CompositeAreaSafetyArchetypeV1.run(),
            try ControllerZoneDistributionArchetypeV1.run()
        ]

        for (offset, receipt) in receipts.enumerated() {
            let payload = try CrossMarketCanonicalV1.data(receipt).base64EncodedString()
            let harness = try makeHarness("c42-atomic-\(offset)")
            defer { try? fileManager.removeItem(at: harness.root) }
            let package = try makeSourcePackage(
                in: harness.root,
                name: "c42-source-\(offset)",
                siteAddress: payload
            )
            let validated = try importPackage(package, into: harness.session)
            let restoredSession = try await BackupRestoreService(
                applicationSupportURL: harness.support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL,
                mode: .emptyInstall
            )
            let restoredPayload = try XCTUnwrap(
                restoredSession.modelContext.fetch(FetchDescriptor<Site>()).first?.address
            )
            XCTAssertEqual(restoredPayload, payload)
            XCTAssertEqual(
                try CrossMarketCanonicalV1.decode(
                    ModelRunReceiptV1.self,
                    from: try XCTUnwrap(Data(base64Encoded: restoredPayload))
                ),
                receipt
            )
            XCTAssertNotEqual(restoredSession.generationID, harness.session.generationID)
            XCTAssertNil(try RestoreIntentStore(applicationSupportURL: harness.support).load())
        }
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testPopulatedIdentityInventorySurvivesPhysicalRestoreAndRejectsTampering() async throws {
        let source = try makeHarness("c13-source")
        let probe = try makeHarness("c13-probe")
        let target = try makeHarness("c13-target")
        defer {
            for harness in [source, probe, target] { try? fileManager.removeItem(at: harness.root) }
        }
        let session = source.session
        let registry = try source.factory.makeGenerationLeaseRegistry()
        let epoch = try XCTUnwrap(session.generationEpoch)
        let lease = try registry.acquireHandle(epoch: epoch, role: .writer)
        defer { try? lease.close() }
        let fence = try source.factory.makeWriterFence(expectedGenerationEpoch: epoch,
            writerLeaseToken: lease.token, registry: registry)
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID,
            allowStateBootstrap: false, staleWriterFence: fence)
        try MutationReceiptRecoveryServiceV1(store: journal).recoverBeforeWriterActivation()
        let initialWriter = try WorkspaceWriterV1(identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: UUID()), clock: S64IdentityClock(),
            idSource: S64IdentityIDs(), fileAuthority: S64IdentityFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext), journalStore: journal)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var assetIDs: [UUID] = []
        for index in 0..<2 {
            let siteID = UUID(), assetID = UUID(), placementID = UUID()
            assetIDs.append(assetID)
            let current = try initialWriter.currentRevision()
            let mutation = try MutationIDV1(rawValue: UUID())
            let expected = try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID,
                generationID: current.generationID, writerInstanceID: current.writerInstanceID,
                workspaceRevision: current.revision, entityRevisions: [
                    .init(identity: WorkspaceEntityIdentityV1(kind: .site, id: siteID), revision: 0),
                    .init(identity: WorkspaceEntityIdentityV1(kind: .asset, id: assetID), revision: 0),
                    .init(identity: WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: placementID), revision: 0),
                ])
            _ = try initialWriter.execute(.init(mutationID: mutation, expectedRevision: expected,
                command: .createFirstSign(.init(siteID: siteID,
                    newSite: .init(id: siteID, label: "Identity site \(index)", address: nil, timeZoneID: "UTC"),
                    assetID: assetID, assetLabel: "Identity asset \(index)",
                    packID: SignPack.illuminatedSignV1.packID,
                    packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                    packContentVersion: SignPack.illuminatedSignV1.contentVersion, createdAt: date,
                    initialPlacementMutationID: mutation, initialPlacementEventID: placementID,
                    initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID())))))
        }
        func export(_ name: String) throws -> URL {
            let destination = source.root.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let exporter = BackupExportService(modelContext: session.modelContext,
                generationRootURL: session.generationRootURL, now: { date.addingTimeInterval(60) })
            let preview = try exporter.prepare()
            return try exporter.export(previewID: preview.id, to: destination)
        }
        let baseline = try importPackage(export("baseline"), into: probe.session)
        let emptyIdentity = try XCTUnwrap(baseline.records.entityIdentityResolution)
        XCTAssertTrue(emptyIdentity.aliasLinks.isEmpty)
        XCTAssertTrue(emptyIdentity.consolidationReceipts.isEmpty)
        XCTAssertTrue(emptyIdentity.mutationReceipts.isEmpty)
        let history = try XCTUnwrap(baseline.records.mutationHistory)
        let workspace = session.workspaceIdentity.workspaceID
        let snapshots = try assetIDs.map { id -> EntityIdentitySnapshotV1 in
            let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: id)
            let terminal = try XCTUnwrap(history.entityRevisions.first { $0.identity == identity })
            let images = try history.receipts.flatMap {
                try MutationReceiptV1.decodeCanonical(from: $0.receiptData).postImages
            }.filter { try $0.identity == identity && $0.revision == terminal.revision }
            XCTAssertEqual(images.count, 1)
            return try EntityIdentitySnapshotV1(workspaceID: workspace, identity: identity,
                revision: terminal.revision, entitySHA256: XCTUnwrap(images.first).semanticSHA256)
        }
        let encoder = BackupCanonicalEncoderV1()
        let atoms = try encoder.entityIdentityResolutionInventoryAtoms(baseline.records)
        XCTAssertEqual(Set(atoms.keys), Set(EntityConsolidationInventoryFamilyV1.allCases))
        XCTAssertTrue(try XCTUnwrap(atoms[.history]).contains { $0.itemID == "lightingDayInventoryWorkflows" })
        XCTAssertTrue(try XCTUnwrap(atoms[.history]).contains { $0.itemID == "lightingNightWorkflows" })
        XCTAssertTrue(try XCTUnwrap(atoms[.evidence]).contains { $0.itemID == "evidenceQuality" })
        XCTAssertTrue(try XCTUnwrap(atoms[.content]).contains { $0.itemID == "fastSurveyInbox" })
        XCTAssertNil(baseline.records.practiceWorkspaceProvenance)
        XCTAssertFalse(try XCTUnwrap(atoms[.history]).contains { $0.itemID == "practiceWorkspaceProvenance" })
        // A category-only optional-provenance probe is not a claim that this REAL source
        // was installed as a practice workspace. The physical package remains unchanged.
        let template = try StarterWorkspaceTemplateReleaseV1(templateID: UUID(), release: 1,
            titleKey: "workspace.starter.practice.title", packageReleaseIDs: ["shipping.illuminated-sign.v1"],
            practiceWatermark: "PRACTICE — NOT FOR FIELD USE")
        let practicePlan = try StarterWorkspaceInstallPlanV1(planID: UUID(), workspaceID: workspace,
            template: template, mutationID: MutationIDV1(rawValue: UUID()), requestedAt: date,
            explicitUserRequest: true, destinationWasEmpty: true)
        let practiceReceipt = try StarterWorkspaceInstallReceiptV1(receiptID: UUID(), plan: practicePlan,
            resultingWorkspaceRevision: 1, installedAt: date.addingTimeInterval(1), disposition: .committed)
        var categoryProbe = baseline.records
        categoryProbe.practiceWorkspaceProvenance = try PracticeWorkspaceBackupSnapshotV1(provenance:
            PracticeWorkspaceProvenanceV1(provenanceID: UUID(), plan: practicePlan,
                receipt: practiceReceipt, revision: 1))
        let optionalAtoms = try encoder.entityIdentityResolutionInventoryAtoms(categoryProbe)
        XCTAssertTrue(try XCTUnwrap(optionalAtoms[.history]).contains { $0.itemID == "practiceWorkspaceProvenance" })
        for family in EntityConsolidationInventoryFamilyV1.allCases {
            XCTAssertEqual(try XCTUnwrap(optionalAtoms[family]).filter { $0.itemID != "practiceWorkspaceProvenance" }, atoms[family])
        }
        let inventory = try EntityConsolidationInventoryBuilderV1.inventory(workspaceID: workspace,
            source: snapshots[0], survivor: snapshots[1], atomsByFamily: atoms)
        // This immutable source-seeding authority is derived from a validated physical package.
        // Public restore below uses its private shipping resolver, not this test helper.
        let resolver = S64PackageIdentityAuthority(snapshots: snapshots, atoms: atoms)
        initialWriter.invalidate()
        let writer = try WorkspaceWriterV1(identity: session.workspaceIdentity, generationID: session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: UUID()), clock: S64IdentityClock(),
            idSource: S64IdentityIDs(), fileAuthority: S64IdentityFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext,
                entityIdentityCanonicalResolver: resolver), journalStore: journal)
        let actor = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspace,
            actor: LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspace, displayName: "Operator"),
            responsibility: .recordedBy, displayNameAtTime: "Operator", capturedAt: date)
        let policy = CanonicalJSONV1.sha256(Data("S64 physical identity policy".utf8))
        func consolidation(_ value: EntityConsolidationInventoryV1) throws -> EntityConsolidationReceiptV1 {
            try .init(consolidationReceiptID: UUID(), workspaceID: workspace,
                source: snapshots[0], survivor: snapshots[1], inventory: value,
                disposition: .consolidated, revision: 1, predecessor: nil, policyVersion: 1,
                policySHA256: policy, recordedBy: actor, recordedAt: date, mutationID: .init(rawValue: UUID()))
        }
        func command(_ payload: EntityIdentityResolutionMutationPayloadV1) throws -> EntityIdentityResolutionMutationCommandV1 {
            try .init(commandID: UUID(), workspaceID: workspace,
                expectedRevision: .init(snapshot: writer.currentRevision()), mutationID: payload.mutationID,
                payload: payload, submittedAt: date)
        }
        let beforeTamper = try writer.currentRevision()
        let beforeTamperRows = try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).map(\.receiptData)
        var tamperedAtoms = atoms
        tamperedAtoms[.content] = []
        let tamperedInventory = try EntityConsolidationInventoryBuilderV1.inventory(workspaceID: workspace,
            source: snapshots[0], survivor: snapshots[1], atomsByFamily: tamperedAtoms)
        XCTAssertNotEqual(tamperedInventory, inventory)
        let hostile = try command(.consolidation(consolidation(tamperedInventory), nil))
        XCTAssertThrowsError(try writer.commitEntityIdentityResolution(hostile))
        XCTAssertEqual(try writer.currentRevision(), beforeTamper)
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).map(\.receiptData), beforeTamperRows)
        let alias = try EntityAliasLinkV1(linkEventID: UUID(), workspaceID: workspace,
            alias: snapshots[0], canonicalEntity: snapshots[1], revision: 1, predecessor: nil,
            reason: .verifiedPriorAlias, policyVersion: 1, policySHA256: policy,
            recordedBy: actor, recordedAt: date, mutationID: .init(rawValue: UUID()))
        _ = try writer.commitEntityIdentityResolution(command(.alias(alias, nil)))
        let effect = try consolidation(inventory)
        _ = try writer.commitEntityIdentityResolution(command(.consolidation(effect, nil)))
        try journal.validateAll()
        let package = try export("populated")
        let originalPackage = try Data(contentsOf: package)
        let validated = try importPackage(package, into: target.session)
        XCTAssertEqual(validated.manifest.source.persistentSchemaVersion, 53)
        XCTAssertEqual(validated.records.recordsSchemaVersion, 52)
        let identity = try XCTUnwrap(validated.records.entityIdentityResolution)
        XCTAssertEqual(identity.aliasLinks, [alias])
        XCTAssertEqual(identity.consolidationReceipts, [effect])
        XCTAssertEqual(identity.mutationReceipts.count, 2)
        let genericIdentityCommands = try XCTUnwrap(validated.records.mutationHistory).receipts.compactMap {
            record -> EntityIdentityResolutionMutationCommandV1? in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyEntityIdentityResolution(command) = envelope.command else { return nil }
            return command
        }
        XCTAssertEqual(genericIdentityCommands.count, 2)
        XCTAssertEqual(Set(genericIdentityCommands.map(\.mutationID)), Set([alias.mutationID, effect.mutationID]))
        for command in genericIdentityCommands {
            let receipt = try XCTUnwrap(identity.mutationReceipts.first { $0.mutationID == command.mutationID })
            XCTAssertNoThrow(try receipt.validate(command: command))
        }
        XCTAssertEqual(try encoder.entityIdentityResolutionInventoryAtoms(validated.records), atoms)
        let restoredInventory = try EntityConsolidationInventoryBuilderV1.inventory(workspaceID: workspace,
            source: snapshots[0], survivor: snapshots[1],
            atomsByFamily: encoder.entityIdentityResolutionInventoryAtoms(validated.records))
        XCTAssertEqual(restoredInventory.items, inventory.items)
        XCTAssertEqual(restoredInventory.inventorySHA256, inventory.inventorySHA256)
        let sourceAliasBytes = try session.modelContext.fetch(FetchDescriptor<EntityAliasLinkRowV1>()).map(\.canonicalData)
        let sourceConsolidationBytes = try session.modelContext.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>()).map(\.canonicalData)
        let sourceTypedBytes = try session.modelContext.fetch(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>()).map(\.canonicalData)
        let sourceJournal = try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
        let envelopeBytes = Set(sourceJournal.map(\.envelopeData))
        let receiptBytes = Set(sourceJournal.map(\.receiptData))
        let restored = try await BackupRestoreService(applicationSupportURL: target.support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })).restore(
                validatedPackage: validated, currentModelContext: target.session.modelContext,
                currentGenerationID: target.session.generationID,
                currentGenerationRootURL: target.session.generationRootURL, mode: .emptyInstall)
        let reopened = try target.factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, restored.generationID)
        XCTAssertNotEqual(reopened.generationID, target.session.generationID)
        let context = reopened.modelContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<EntityAliasLinkRowV1>()).map(\.canonicalData), sourceAliasBytes)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>()).map(\.canonicalData), sourceConsolidationBytes)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>()).map(\.canonicalData)), Set(sourceTypedBytes))
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Asset>()).map(\.id)), Set(assetIDs))
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Asset>()).map(\.label)), Set(["Identity asset 0", "Identity asset 1"]))
        let restoredJournal = try context.fetch(FetchDescriptor<MutationReceiptRow>())
        XCTAssertEqual(Set(restoredJournal.map(\.envelopeData)), envelopeBytes)
        XCTAssertEqual(Set(restoredJournal.map(\.receiptData)), receiptBytes)
        try MutationJournalStoreV1(modelContext: context, identity: reopened.workspaceIdentity,
            generationID: reopened.generationID, allowStateBootstrap: false).validateAll()
        for mode in [BackupRestoreMode.clone, .fork] {
            let rejected = try makeHarness("c13-reject-\(mode.rawValue)")
            defer { try? fileManager.removeItem(at: rejected.root) }
            let sentinelSiteID = UUID(), sentinelAssetID = UUID(), sentinelPlacementID = UUID()
            let destinationRegistry = try rejected.factory.makeGenerationLeaseRegistry()
            let destinationEpoch = try XCTUnwrap(rejected.session.generationEpoch)
            let destinationLease = try destinationRegistry.acquireHandle(epoch: destinationEpoch, role: .writer)
            defer { try? destinationLease.close() }
            let destinationFence = try rejected.factory.makeWriterFence(expectedGenerationEpoch: destinationEpoch,
                writerLeaseToken: destinationLease.token, registry: destinationRegistry)
            let destinationJournal = try MutationJournalStoreV1(modelContext: rejected.session.modelContext,
                identity: rejected.session.workspaceIdentity, generationID: rejected.session.generationID,
                allowStateBootstrap: false, staleWriterFence: destinationFence)
            try MutationReceiptRecoveryServiceV1(store: destinationJournal).recoverBeforeWriterActivation()
            let destinationWriter = try WorkspaceWriterV1(identity: rejected.session.workspaceIdentity,
                generationID: rejected.session.generationID,
                initialRevision: destinationJournal.currentRevision(writerInstanceID: UUID()),
                clock: S64IdentityClock(), idSource: S64IdentityIDs(), fileAuthority: S64IdentityFiles(),
                adapter: WorkspaceWriterAdapterV1(modelContext: rejected.session.modelContext),
                journalStore: destinationJournal)
            let destinationRevision = try destinationWriter.currentRevision()
            let sentinelMutation = try MutationIDV1(rawValue: UUID())
            let sentinelExpected = try WorkspaceExpectedRevisionV1(workspaceID: destinationRevision.workspaceID,
                generationID: destinationRevision.generationID, writerInstanceID: destinationRevision.writerInstanceID,
                workspaceRevision: destinationRevision.revision, entityRevisions: [
                    .init(identity: WorkspaceEntityIdentityV1(kind: .site, id: sentinelSiteID), revision: 0),
                    .init(identity: WorkspaceEntityIdentityV1(kind: .asset, id: sentinelAssetID), revision: 0),
                    .init(identity: WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: sentinelPlacementID), revision: 0),
                ])
            _ = try destinationWriter.execute(.init(mutationID: sentinelMutation, expectedRevision: sentinelExpected,
                command: .createFirstSign(.init(siteID: sentinelSiteID,
                    newSite: .init(id: sentinelSiteID, label: "Preserved destination", address: nil, timeZoneID: "UTC"),
                    assetID: sentinelAssetID, assetLabel: "Preserved destination asset",
                    packID: SignPack.illuminatedSignV1.packID,
                    packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                    packContentVersion: SignPack.illuminatedSignV1.contentVersion, createdAt: date,
                    initialPlacementMutationID: sentinelMutation, initialPlacementEventID: sentinelPlacementID,
                    initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID())))))
            try destinationJournal.validateAll()
            let sentinelRows = try rejected.session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
            let sentinelEnvelopes = Set(sentinelRows.map(\.envelopeData))
            let sentinelReceipts = Set(sentinelRows.map(\.receiptData))
            XCTAssertEqual(sentinelRows.count, 1)
            destinationWriter.invalidate()
            try destinationLease.close()
            let staged = try importPackage(package, into: rejected.session)
            // The same checkpoint validation reached by clone/fork must already pass.
            let destinationReadJournal = try MutationJournalStoreV1(modelContext: rejected.session.modelContext,
                identity: rejected.session.workspaceIdentity, generationID: rejected.session.generationID,
                allowStateBootstrap: false)
            try destinationReadJournal.validateAll()
            do {
                _ = try await BackupRestoreService(applicationSupportURL: rejected.support,
                    storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })).restore(
                        validatedPackage: staged, currentModelContext: rejected.session.modelContext,
                        currentGenerationID: rejected.session.generationID,
                        currentGenerationRootURL: rejected.session.generationRootURL, mode: mode)
                XCTFail("Populated C13 must not clone or fork")
            } catch {
                XCTAssertEqual(error as? BackupRestoreServiceError, .invalidRestoreAuthority)
            }
            XCTAssertEqual(try rejected.factory.openOrBootstrapCurrent().generationID, rejected.session.generationID)
            XCTAssertEqual(try rejected.session.modelContext.fetch(FetchDescriptor<Site>()).map(\.id), [sentinelSiteID])
            XCTAssertEqual(try rejected.session.modelContext.fetch(FetchDescriptor<Site>()).map(\.label), ["Preserved destination"])
            XCTAssertEqual(try rejected.session.modelContext.fetch(FetchDescriptor<Asset>()).map(\.id), [sentinelAssetID])
            XCTAssertEqual(try rejected.session.modelContext.fetch(FetchDescriptor<Asset>()).map(\.label), ["Preserved destination asset"])
            let unchangedJournal = try rejected.session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
            XCTAssertEqual(Set(unchangedJournal.map(\.envelopeData)), sentinelEnvelopes)
            XCTAssertEqual(Set(unchangedJournal.map(\.receiptData)), sentinelReceipts)
            try destinationReadJournal.validateAll()
            XCTAssertTrue(try rejected.session.modelContext.fetch(FetchDescriptor<EntityAliasLinkRowV1>()).isEmpty)
        }
        XCTAssertEqual(try Data(contentsOf: package), originalPackage)
        XCTAssertEqual(Set(try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).map(\.receiptData)), receiptBytes)
    }
}

private struct S64IdentityClock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}
private struct S64IdentityIDs: ApplicationIDSource { func makeID() -> UUID { UUID() } }
private struct S64IdentityFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private struct S64NoopAuthentication: LocalAuthenticationClient {
    func availability() async -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .none)
    }

    func authenticate(_ attempt: LocalAuthenticationAttemptV1) async -> LocalAuthenticationOutcomeV1 {
        .userCancelled
    }

    func cancel(attemptID: UUID) async {}
}

private actor S64SuspendingAccessibleDocumentResolver: AccessibleDocumentSemanticTreeResolvingV1 {
    private let tree: AccessibleDocumentSemanticTreeV1
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var resolutionWaiters: [CheckedContinuation<Void, Never>] = []
    private var requested = false
    private var released = false

    init(tree: AccessibleDocumentSemanticTreeV1) {
        self.tree = tree
    }

    func resolve(
        _ request: AccessibleDocumentSemanticTreeResolutionRequestV1
    ) async throws -> AccessibleDocumentSemanticTreeV1 {
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !released {
            await withCheckedContinuation { resolutionWaiters.append($0) }
        }
        return tree
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func resume() {
        released = true
        let waiters = resolutionWaiters
        resolutionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class S64PackageIdentityAuthority: EntityIdentityResolutionCanonicalSourceResolvingV1 {
    let snapshots: [EntityIdentitySnapshotV1]
    let atoms: [EntityConsolidationInventoryFamilyV1: [EntityConsolidationInventoryAtomV1]]
    init(snapshots: [EntityIdentitySnapshotV1], atoms: [EntityConsolidationInventoryFamilyV1: [EntityConsolidationInventoryAtomV1]]) {
        self.snapshots = snapshots; self.atoms = atoms
    }
    func resolveEntityIdentity(_ identity: WorkspaceEntityIdentityV1, workspaceID: WorkspaceID,
        revision: UInt64) throws -> EntityIdentitySnapshotV1 {
        guard let value = snapshots.first(where: { $0.identity == identity && $0.workspaceID == workspaceID && $0.revision == revision }) else {
            throw EntityIdentityResolutionFailureV1.staleRevision
        }
        return value
    }
    func aliasPath(from alias: WorkspaceEntityIdentityV1, workspaceID: WorkspaceID) throws -> [WorkspaceEntityIdentityV1] {
        guard snapshots.contains(where: { $0.identity == alias && $0.workspaceID == workspaceID }) else {
            throw EntityIdentityResolutionFailureV1.wrongWorkspace
        }
        return [] // The independently validated baseline package has no C13 aliases.
    }
    func canonicalConsolidationAtoms(source: EntityIdentitySnapshotV1, survivor: EntityIdentitySnapshotV1,
        family: EntityConsolidationInventoryFamilyV1) throws -> [EntityConsolidationInventoryAtomV1] {
        guard source == snapshots[0], survivor == snapshots[1], let values = atoms[family] else {
            throw EntityIdentityResolutionFailureV1.incompleteInventory
        }
        return values
    }
    func resolve(workspaceID: WorkspaceID, entityID: WorkspaceEntityIdentityV1,
        expectedRevision: UInt64) throws -> EntityIdentityResolutionCanonicalSourceV1 {
        let snapshot = try resolveEntityIdentity(entityID, workspaceID: workspaceID, revision: expectedRevision)
        let inventory = try EntityConsolidationInventoryBuilderV1.inventory(workspaceID: workspaceID,
            source: snapshots[0], survivor: snapshots[1], atomsByFamily: atoms)
        return try .init(snapshot: snapshot, inventory: inventory)
    }
}

private final class C33TemporalEvidenceAnchorS64AtomicRestore: XCTestCase {
    func testC33S64AtomicRestoreCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "restore.atomic.temporal-evidence",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "restore.atomic.temporal-evidence",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorS64AtomicRestore: XCTestCase {
    func testC32S64AtomicRestoreCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .site,
            fieldID: "restore.atomic-receipt",
            value: .text("restored accepted value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .site,
            fieldID: "restore.atomic-receipt",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46S64AtomicRestoreCompatibilityTests: XCTestCase {
    func testC46AtomicRestoreKeepsStableContactIdentity() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "atomic-restore",
            kind: .email,
            handoff: .email,
            slot: 46404
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift_Tests: XCTestCase {
    func testC47S64AtomicRestoreTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_4AtomicRestoreTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

private final class C48PortableReviewS64AtomicRestoreBoundaryTests: XCTestCase {
    func testC48RestoreSidecarContractRequiresExactBytesAndCloneForkInvalidation() {
        XCTAssertTrue(BackupRestoreFailurePoint.allCases.contains(.afterPointerSwitch))
        XCTAssertTrue(C48PortableExchangeMigrationBoundaryV2.preservesExactBytes)
        XCTAssertTrue(C48PortableExchangeMigrationBoundaryV2.cloneOrForkInvalidatesCapabilities)
        XCTAssertFalse(C48PortableExchangeMigrationBoundaryV2.canonicalSwiftDataSchemaChanged)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.sessionStoreIsNonpersistent)
    }
}
private final class C49WorkResourceAtomicRestoreBoundaryTests: XCTestCase {
    func testRestoreRetainsAppendOnlyManualResourceSemantics() {
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.appendOnly)
        XCTAssertEqual(C49WorkResourceContractBoundaryV1.soleWriter, "WorkspaceWriterV1")
        XCTAssertTrue(C49WorkResourceLifecycleBoundaryV1.backupRestoreCloneForkDeleteAndEraseAreExplicit)
    }
}

private final class C50IncumbentAdapterS64AtomicRestoreBoundaryTests: XCTestCase {
    func testAtomicRestoreDoesNotReenableSelectionOrCopyExternalAuthority() {
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .replaceExisting))
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .clone))
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .fork))
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.cloneForkCopiesSecurityBookmarks)
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.replacementRestoresProfileActivation)
    }
}

extension C45AtomicRestoreCompatibilityTests {
    func testV23P03C51RestoreRebindsCalendarBasisAtomically() throws {
        try ScheduleRestoreIdentityPolicyV1.validate()
        XCTAssertTrue(
            ScheduleRestoreIdentityPolicyV1.calendarOverrideAndBasisClosureReboundAtomically
                && ScheduleRestoreIdentityPolicyV1
                    .allDaysCompatibilityPreservesOccurrenceIdentityAndDate
                && !ScheduleReplacementRestorePolicyV1.derivedProjectionsRestored
        )
    }
}


extension S6_4AtomicRestoreTests {
    @MainActor
    func testPreparedRestorePublishesRealDraftBytesAndRequiresBindingBeforeCleanup() async throws {
        let source = try makeHarness("draft-publication-source")
        defer { try? fileManager.removeItem(at: source.root) }
        let session = source.session
        let workspace = session.workspaceIdentity.workspaceID
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try C36FieldDraftTestSupportV1.makeFixture()
        let adapter = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: source.support, workspaceID: workspace, clock: { date }
        )
        let bytes = Data("physical draft attachment retained across prepared restore".utf8)
        let item = try await adapter.stage(data: bytes, draftID: UUID(),
            workspaceID: workspace, attachmentKind: .file)
        let checkpoint = try FieldDraftCheckpointV1(
            draftID: item.draftID, workspaceID: workspace,
            scope: fixture.activeCheckpoint.scope, purpose: fixture.activeCheckpoint.purpose,
            codec: fixture.activeCheckpoint.codec, baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: fixture.activeCheckpoint.payloadData, stageIDs: [item.stageID],
            resumeAnchor: fixture.activeCheckpoint.resumeAnchor, state: .active,
            updatedAt: date, mutationID: MutationIDV1(rawValue: UUID())
        )
        let registry = try source.factory.makeGenerationLeaseRegistry()
        let epoch = try XCTUnwrap(session.generationEpoch)
        let lease = try registry.acquireHandle(epoch: epoch, role: .writer)
        defer { try? lease.close() }
        let fence = try source.factory.makeWriterFence(expectedGenerationEpoch: epoch,
            writerLeaseToken: lease.token, registry: registry)
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID,
            allowStateBootstrap: false, staleWriterFence: fence)
        try MutationReceiptRecoveryServiceV1(store: journal).recoverBeforeWriterActivation()
        let writer = try WorkspaceWriterV1(identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: UUID()),
            clock: S64IdentityClock(), idSource: S64IdentityIDs(), fileAuthority: S64IdentityFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext), journalStore: journal)
        let payloads: [FieldDraftMutationPayloadV1] = [.createCheckpoint(checkpoint), .appendStagingItem(item)]
        for payload in payloads {
            let mutation = try FieldDraftMutationV1(workspaceID: workspace, expectedRevision: 0,
                expectedBaseCanonicalRevision: 0, mutationID: payload.mutationID, postImage: payload)
            let current = try writer.currentRevision()
            let identity = try mutation.concurrencyIdentity
            let expected = try WorkspaceExpectedRevisionV1(workspaceID: workspace,
                generationID: current.generationID, writerInstanceID: current.writerInstanceID,
                workspaceRevision: current.revision,
                entityRevisions: [.init(identity: identity, revision: 0)])
            let result = try writer.execute(.init(mutationID: mutation.mutationID,
                expectedRevision: expected, command: .applyFieldDraft(mutation)))
            XCTAssertEqual(result.mutationID, mutation.mutationID)
            let durable = try XCTUnwrap(journal.receipt(mutationID: mutation.mutationID))
            XCTAssertEqual(durable.mutationID, mutation.mutationID)
        }
        let destination = source.root.appendingPathComponent("export")
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let exporter = BackupExportService(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL, now: { date.addingTimeInterval(60) })
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: destination)
        for point in [BackupRestoreFailurePoint.afterPreparedWrite, .beforeGenerationInstall] {
            let target = try makeHarness("draft-publication-\(point)")
            defer { try? fileManager.removeItem(at: target.root) }
            let validated = try importPackage(package, into: target.session)
            XCTAssertEqual(validated.records.fieldDrafts.count, 2)
            let restoreID = UUID(), newGenerationID = UUID()
            let service = try BackupRestoreService(applicationSupportURL: target.support,
                makeUUID: sequence([newGenerationID, restoreID]),
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point))
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(validatedPackage: validated,
                    currentModelContext: target.session.modelContext,
                    currentGenerationID: target.session.generationID,
                    currentGenerationRootURL: target.session.generationRootURL)
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
            }
            let intentStore = try RestoreIntentStore(applicationSupportURL: target.support)
            let intent = try XCTUnwrap(intentStore.load())
            XCTAssertEqual(intent.phase, .prepared)
            let bindingURL = target.support.appendingPathComponent(
                "FieldEvidenceRestore/draft-publication-\(intent.restoreID.uuidString.lowercased()).json"
            )
            let recovery = try BackupRestoreService(applicationSupportURL: target.support)
            if point == .afterPreparedWrite {
                XCTAssertTrue(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
                XCTAssertFalse(fileManager.fileExists(atPath: bindingURL.path))
                // An existing invalid binding must stop synchronous recovery
                // before it discards the only imported source package.
                try Data("{}".utf8).write(to: bindingURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: bindingURL)
                let packageBefore = try tree(validated.stagedPackageURL)
                XCTAssertThrowsError(try recovery.reconcileAtStartup())
                XCTAssertEqual(try tree(validated.stagedPackageURL), packageBefore)
                XCTAssertEqual(try intentStore.load(), intent)
                try fileManager.removeItem(at: bindingURL)
            } else {
                // The ordinary restore call has already published and bound
                // actual bytes before reaching the pre-install interruption.
                XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(
                    with: Data(contentsOf: bindingURL)) as? [String: Any])
                let receiptData = try JSONSerialization.data(withJSONObject: XCTUnwrap(object["receipt"]))
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                let receipt = try decoder.decode(DraftAttachmentRestorePublicationReceiptV1.self,
                    from: receiptData)
                try receipt.validate()
                XCTAssertEqual(receipt.restoreID, intent.restoreID)
                XCTAssertEqual(receipt.workspaceID, workspace)
                XCTAssertEqual(receipt.adoptedStageIDs, [item.stageID])
                XCTAssertTrue(receipt.reusedStageIDs.isEmpty)
                XCTAssertFalse(receipt.atomicAcrossRoots)
                XCTAssertTrue(receipt.canonicalCommitRequired)
            }
            // Startup owns the derived-state cleanup and intent retirement;
            // recovery must go through the production async bridge.
            let noFurtherRecovery = try await recovery
                .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            XCTAssertNil(noFurtherRecovery)
            XCTAssertEqual(try target.factory.currentGenerationID(), target.session.generationID)
            XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
            XCTAssertFalse(fileManager.fileExists(atPath: bindingURL.path))
            XCTAssertNil(try intentStore.load())
            let reopened = try DraftAttachmentStagingAdapterV1(
                applicationSupportURL: target.support, workspaceID: workspace
            )
            let entries = try await reopened.entries()
            let retained = try await reopened.data(stageID: item.stageID)
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries.first?.item.workspaceID, workspace)
            XCTAssertEqual(entries.first?.item.contentDigest, item.contentDigest)
            XCTAssertEqual(entries.first?.item.actualByteCount, Int64(bytes.count))
            XCTAssertEqual(retained, bytes)
            XCTAssertEqual(try target.session.modelContext.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()), 0)
            let noFurtherRecoveryAgain = try await recovery
                .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            XCTAssertNil(noFurtherRecoveryAgain)
            let retainedAgain = try await reopened.data(stageID: item.stageID)
            XCTAssertEqual(retainedAgain, bytes)
        }
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testConfigurationCloneEmptyRootsRecoverAcrossPublicationBoundaries() async throws {
        let source = try makeHarness("clone-empty-boundaries-source")
        addTeardownBlock { [root = source.root] in
            try? FileManager.default.removeItem(at: root)
        }
        let draft = try await makeConfigurationCloneDraftPackage(in: source)
        let archive = try Data(contentsOf: draft.package)
        let points: [BackupRestoreFailurePoint] = [
            .afterPreparedWrite, .beforeGenerationInstall, .afterPointerSwitch, .beforeCleanup
        ]
        for existingEmptyRoot in [false, true] {
            for point in points {
                let target = try makeHarness("clone-empty-\(existingEmptyRoot)-\(point)")
                addTeardownBlock { [root = target.root] in
                    try? FileManager.default.removeItem(at: root)
                }
                if existingEmptyRoot {
                    _ = try DraftAttachmentStagingAdapterV1(applicationSupportURL: target.support,
                        workspaceID: target.session.workspaceID)
                }
                let rootBefore = existingEmptyRoot ? try tree(configurationCloneDraftRoot(target.support)) : []
                let validated = try importPackage(draft.package, into: target.session)
                let service = try BackupRestoreService(applicationSupportURL: target.support,
                    failureInjection: .init(failOnceAt: point))
                await XCTAssertThrowsErrorAsync {
                    _ = try await service.restore(validatedPackage: validated,
                        currentModelContext: target.session.modelContext,
                        currentGenerationID: target.session.generationID,
                        currentGenerationRootURL: target.session.generationRootURL, mode: .clone)
                } verify: { XCTAssertEqual($0 as? BackupRestoreServiceError, .injectedFailure) }
                let intents = try RestoreIntentStore(applicationSupportURL: target.support)
                let intent = try XCTUnwrap(intents.load())
                let recovery = try BackupRestoreService(applicationSupportURL: target.support)
                let synchronous = try recovery.reconcileAtStartup()
                if point == .afterPreparedWrite || point == .beforeGenerationInstall {
                    XCTAssertNil(synchronous)
                    XCTAssertEqual(try target.factory.currentGenerationID(), target.session.generationID)
                    XCTAssertNil(try intents.load())
                } else {
                    let selected = try XCTUnwrap(synchronous)
                    XCTAssertEqual(selected.generationID, intent.newGenerationID)
                    XCTAssertNotEqual(selected.workspaceID, target.session.workspaceID)
                    let cloneIdentity = try XCTUnwrap(intent.identity)
                    let projected = try recovery.c55CurrentRecordsForTesting(in: selected.modelContext)
                    try assertConfigurationCloneStockDestinationPolicy(
                        source: validated.records, projected: projected, identity: cloneIdentity)
                    try assertNoConfigurationCloneDraftRows(in: selected.modelContext)
                    XCTAssertEqual(try intents.load()?.phase, .newGenerationValidated)
                    let completed = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
                    XCTAssertEqual(completed?.generationID, selected.generationID)
                    XCTAssertNil(try intents.load())
                    let reopened = try target.factory.openOrBootstrapCurrent()
                    XCTAssertEqual(reopened.generationID, selected.generationID)
                    try assertNoConfigurationCloneDraftRows(in: reopened.modelContext)
                }
                XCTAssertEqual(fileManager.fileExists(atPath: configurationCloneDraftRoot(target.support).path), existingEmptyRoot)
                if existingEmptyRoot { XCTAssertEqual(try tree(configurationCloneDraftRoot(target.support)), rootBefore) }
                XCTAssertEqual(try Data(contentsOf: draft.package), archive)
                try await assertConfigurationCloneDraftSourceUnchanged(source, draft: draft)
            }
        }
    }

    @MainActor
    func testConfigurationCloneColdRecoveryRejectsNewStagingWithoutDeletingIt() async throws {
        let source = try makeHarness("clone-cold-stage-source")
        addTeardownBlock { [root = source.root] in
            try? FileManager.default.removeItem(at: root)
        }
        let draft = try await makeConfigurationCloneDraftPackage(in: source)
        for point in [BackupRestoreFailurePoint.afterPreparedWrite, .afterPointerSwitch] {
            let target = try makeHarness("clone-cold-stage-\(point)")
            addTeardownBlock { [root = target.root] in
                try? FileManager.default.removeItem(at: root)
            }
            let validated = try importPackage(draft.package, into: target.session)
            let service = try BackupRestoreService(applicationSupportURL: target.support,
                failureInjection: .init(failOnceAt: point))
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(validatedPackage: validated,
                    currentModelContext: target.session.modelContext,
                    currentGenerationID: target.session.generationID,
                    currentGenerationRootURL: target.session.generationRootURL, mode: .clone)
            } verify: { XCTAssertEqual($0 as? BackupRestoreServiceError, .injectedFailure) }
            let staging = try DraftAttachmentStagingAdapterV1(applicationSupportURL: target.support,
                workspaceID: target.session.workspaceID)
            let payload = Data("new current-root bytes must survive a denied clone recovery".utf8)
            let item = try await staging.stage(data: payload, draftID: UUID(),
                workspaceID: target.session.workspaceID, attachmentKind: .file)
            let before = try tree(target.support)
            let currentID = try target.factory.currentGenerationID()
            let intents = try RestoreIntentStore(applicationSupportURL: target.support)
            let intent = try XCTUnwrap(intents.load())
            let recovery = try BackupRestoreService(applicationSupportURL: target.support)
            XCTAssertThrowsError(try recovery.reconcileAtStartup())
            await XCTAssertThrowsErrorAsync {
                _ = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            } verify: { _ in }
            XCTAssertEqual(try intents.load(), intent)
            XCTAssertEqual(try target.factory.currentGenerationID(), currentID)
            XCTAssertEqual(try tree(target.support), before)
            let retained = try await staging.data(stageID: item.stageID)
            XCTAssertEqual(retained, payload)
            try await assertConfigurationCloneDraftSourceUnchanged(source, draft: draft)
        }
    }

    @MainActor
    func testConfigurationCloneRechecksAccessCancellationAndRootAfterMediaCopy() async throws {
        let source = try makeHarness("clone-media-boundary-source")
        addTeardownBlock { [root = source.root] in
            try? FileManager.default.removeItem(at: root)
        }
        let draft = try await makeConfigurationCloneDraftPackage(in: source)
        for scenario in ["access", "cancellation", "staging"] {
            let target = try makeHarness("clone-media-boundary-\(scenario)")
            addTeardownBlock { [root = target.root] in
                try? FileManager.default.removeItem(at: root)
            }
            let validated = try importPackage(draft.package, into: target.session)
            let service = try BackupRestoreService(applicationSupportURL: target.support)
            let currentBefore = try tree(target.session.generationRootURL)
            var reached = false, accessAllowed = true
            var staged: (DraftAttachmentStagingAdapterV1, AttachmentStagingItemV1)?
            let hostileBytes = Data("stage during clone media suspension".utf8)
            service.configurationCloneObservationForTesting = { point in
                guard point == .afterFinalMediaCopy else { return }
                reached = true
                if scenario == "access" { accessAllowed = false }
                else if scenario == "cancellation" { withUnsafeCurrentTask { $0?.cancel() } }
                else {
                    let owner = try DraftAttachmentStagingAdapterV1(applicationSupportURL: target.support,
                        workspaceID: target.session.workspaceID)
                    let item = try await owner.stage(data: hostileBytes, draftID: UUID(),
                        workspaceID: target.session.workspaceID, attachmentKind: .file)
                    staged = (owner, item)
                }
            }
            let operation = Task { @MainActor in
                try await service.restore(validatedPackage: validated,
                    currentModelContext: target.session.modelContext,
                    currentGenerationID: target.session.generationID,
                    currentGenerationRootURL: target.session.generationRootURL, mode: .clone,
                    validateAccess: {
                        if !accessAllowed { throw AppAccessContractFailureV1.accessDenied }
                    })
            }
            await XCTAssertThrowsErrorAsync { _ = try await operation.value } verify: { error in
                if scenario == "access" { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
                if scenario == "cancellation" { XCTAssertTrue(error is CancellationError) }
            }
            XCTAssertTrue(reached)
            XCTAssertEqual(try target.factory.currentGenerationID(), target.session.generationID)
            XCTAssertEqual(try tree(target.session.generationRootURL), currentBefore)
            XCTAssertNil(try RestoreIntentStore(applicationSupportURL: target.support).load())
            if let (owner, item) = staged {
                let bytes = try await owner.data(stageID: item.stageID)
                XCTAssertEqual(bytes, hostileBytes)
            }
            try await assertConfigurationCloneDraftSourceUnchanged(source, draft: draft)
        }
    }

    @MainActor
    func testConfigurationCloneRetainsIntentWhenStagingChangesDuringFinalColdCleanup() async throws {
        let source = try makeHarness("clone-final-cold-source")
        let target = try makeHarness("clone-final-cold-target")
        addTeardownBlock { [sourceRoot = source.root, targetRoot = target.root] in
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let draft = try await makeConfigurationCloneDraftPackage(in: source)
        let staging = try DraftAttachmentStagingAdapterV1(applicationSupportURL: target.support,
            workspaceID: target.session.workspaceID)
        let validated = try importPackage(draft.package, into: target.session)
        let service = try BackupRestoreService(applicationSupportURL: target.support,
            failureInjection: .init(failOnceAt: .afterPointerSwitch))
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(validatedPackage: validated,
                currentModelContext: target.session.modelContext,
                currentGenerationID: target.session.generationID,
                currentGenerationRootURL: target.session.generationRootURL, mode: .clone)
        } verify: { XCTAssertEqual($0 as? BackupRestoreServiceError, .injectedFailure) }
        let intents = try RestoreIntentStore(applicationSupportURL: target.support)
        let original = try XCTUnwrap(intents.load())
        let recovery = try BackupRestoreService(applicationSupportURL: target.support)
        var item: AttachmentStagingItemV1?
        let bytes = Data("late staging must not be erased or accepted as clone state".utf8)
        recovery.configurationCloneObservationForTesting = { point in
            guard point == .afterFinalCleanup else { return }
            item = try await staging.stage(data: bytes, draftID: UUID(),
                workspaceID: target.session.workspaceID, attachmentKind: .file)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
        } verify: { _ in }
        let staged = try XCTUnwrap(item)
        let retained = try await staging.data(stageID: staged.stageID)
        XCTAssertEqual(retained, bytes)
        XCTAssertEqual(try intents.load(), original.advancing(to: .newGenerationValidated))
        XCTAssertEqual(try target.factory.currentGenerationID(), original.newGenerationID)
        let after = try tree(target.support)
        recovery.configurationCloneObservationForTesting = nil
        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(try tree(target.support), after)
        try await assertConfigurationCloneDraftSourceUnchanged(source, draft: draft)
    }

    @MainActor
    func testConfigurationCloneFrozenEvidenceValidationIsBoundedAndRejectsHostileFiles() async throws {
        let target = try makeHarness("clone-bounded-evidence")
        defer { try? fileManager.removeItem(at: target.root) }
        let service = try BackupRestoreService(applicationSupportURL: target.support)
        let root = target.session.generationRootURL
        let path = "frozen-evidence.jpg", url = root.appendingPathComponent(path)
        let bytes = Data(repeating: 0x58, count: 32 * 1024 * 1024)
        let digest = CanonicalJSONV1.sha256(bytes)
        try bytes.write(to: url)
        var checks = 0
        try service.c36ValidateFrozenEvidenceFileForTesting(root: root, relativePath: path,
            expectedByteCount: bytes.count, expectedSHA256: digest, authorityCheck: { checks += 1 })
        XCTAssertGreaterThanOrEqual(checks, bytes.count / (64 * 1024))
        let cancelled = Task { @MainActor in
            var observed = 0
            try service.c36ValidateFrozenEvidenceFileForTesting(root: root, relativePath: path,
                expectedByteCount: bytes.count, expectedSHA256: digest, authorityCheck: {
                    observed += 1
                    if observed == 20 { withUnsafeCurrentTask { $0?.cancel() } }
                })
        }
        await XCTAssertThrowsErrorAsync { try await cancelled.value } verify: { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        for kind in ["fifo", "symlink", "hardlink"] {
            let hostile = root.appendingPathComponent("hostile-\(kind).jpg")
            if kind == "fifo" { XCTAssertEqual(Darwin.mkfifo(hostile.path, mode_t(0o600)), 0) }
            else if kind == "symlink" { try fileManager.createSymbolicLink(at: hostile, withDestinationURL: url) }
            else { XCTAssertEqual(Darwin.link(url.path, hostile.path), 0) }
            XCTAssertThrowsError(try service.c36ValidateFrozenEvidenceFileForTesting(root: root,
                relativePath: hostile.lastPathComponent, expectedByteCount: bytes.count, expectedSHA256: digest))
            try fileManager.removeItem(at: hostile)
        }
        let replacement = root.appendingPathComponent("same-bytes-replacement.jpg")
        try bytes.write(to: replacement)
        var replaced = false, observations = 0
        XCTAssertThrowsError(try service.c36ValidateFrozenEvidenceFileForTesting(root: root,
            relativePath: path, expectedByteCount: bytes.count, expectedSHA256: digest,
            authorityCheck: {
                observations += 1
                if observations == 20 {
                    XCTAssertEqual(Darwin.rename(replacement.path, url.path), 0)
                    replaced = true
                }
            }))
        XCTAssertTrue(replaced)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor
    func testConfigurationCloneOmitsDraftRowsAndStagedBytesWithoutChangingSource() async throws {
        let source = try makeHarness("configuration-clone-draft-source")
        defer { try? fileManager.removeItem(at: source.root) }
        let draft = try await makeConfigurationCloneDraftPackage(in: source)
        let archiveBefore = try Data(contentsOf: draft.package)
        let target = try makeHarness("configuration-clone-draft-target")
        defer { try? fileManager.removeItem(at: target.root) }
        let validated = try importPackage(draft.package, into: target.session)
        XCTAssertEqual(validated.records.fieldDrafts.count, 2)
        XCTAssertFalse(validated.members.keys.filter { $0.hasPrefix("draft-staging/") }.isEmpty)
        let service = try BackupRestoreService(applicationSupportURL: target.support)

        let restored = try await service.restore(validatedPackage: validated,
            currentModelContext: target.session.modelContext,
            currentGenerationID: target.session.generationID,
            currentGenerationRootURL: target.session.generationRootURL, mode: .clone)

        XCTAssertNotEqual(restored.workspaceID, source.session.workspaceID)
        try assertNoConfigurationCloneDraftRows(in: restored.modelContext)
        XCTAssertFalse(fileManager.fileExists(atPath: configurationCloneDraftRoot(target.support).path))
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: target.support).load())
        XCTAssertEqual(try Data(contentsOf: draft.package), archiveBefore)
        try await assertConfigurationCloneDraftSourceUnchanged(source, draft: draft)
    }

    @MainActor
    func testEmptyInstallAndForkRetainDraftCheckpointAndOriginalBytes() async throws {
        let source = try makeHarness("non-clone-draft-source")
        defer { try? fileManager.removeItem(at: source.root) }
        let draft = try await makeConfigurationCloneDraftPackage(in: source)
        for mode in [BackupRestoreMode.emptyInstall, .fork] {
            let target = try makeHarness("non-clone-draft-\(mode.rawValue)")
            defer { try? fileManager.removeItem(at: target.root) }
            let validated = try importPackage(draft.package, into: target.session)
            let restored = try await BackupRestoreService(applicationSupportURL: target.support)
                .restore(validatedPackage: validated,
                    currentModelContext: target.session.modelContext,
                    currentGenerationID: target.session.generationID,
                    currentGenerationRootURL: target.session.generationRootURL, mode: mode)
            let checkpoints = try restored.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
            let stages = try restored.modelContext.fetch(FetchDescriptor<AttachmentStagingItemRow>())
            XCTAssertEqual(checkpoints.count, 1)
            XCTAssertEqual(stages.count, 1)
            let checkpoint = try XCTUnwrap(checkpoints.first).value()
            let item = try XCTUnwrap(stages.first).value()
            XCTAssertEqual(checkpoint.workspaceID, restored.workspaceID)
            XCTAssertEqual(item.workspaceID, restored.workspaceID)
            XCTAssertEqual(checkpoint.stageIDs, [item.stageID])
            XCTAssertEqual(item.draftID, checkpoint.draftID)
            XCTAssertEqual(checkpoint.payloadData, draft.checkpoint.payloadData)
            XCTAssertEqual(checkpoint.baseCanonicalRevision, draft.checkpoint.baseCanonicalRevision)
            XCTAssertEqual(checkpoint.draftRevision, draft.checkpoint.draftRevision)
            if mode == .emptyInstall {
                XCTAssertEqual(checkpoint, draft.checkpoint)
                XCTAssertEqual(item, draft.item)
            } else {
                XCTAssertNotEqual(checkpoint.draftID, draft.checkpoint.draftID)
                XCTAssertNotEqual(item.stageID, draft.item.stageID)
                XCTAssertEqual(checkpoint.state, .recoveryRequired)
                XCTAssertNil(checkpoint.lastDurableMutationID)
                XCTAssertNil(checkpoint.lastReceiptSHA256)
            }
            let staging = try DraftAttachmentStagingAdapterV1(
                applicationSupportURL: target.support, workspaceID: restored.workspaceID)
            let bytes = try await staging.data(stageID: item.stageID)
            XCTAssertEqual(bytes, draft.bytes)
            let entries = try await staging.entries()
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries.first?.item, item)
            try await assertConfigurationCloneDraftSourceUnchanged(source, draft: draft)
        }
    }

    @MainActor
    func testConfigurationClonePreparedRecoveryNeverPublishesOmittedDraftBytes() async throws {
        let source = try makeHarness("configuration-clone-recovery-source")
        defer { try? fileManager.removeItem(at: source.root) }
        let draft = try await makeConfigurationCloneDraftPackage(in: source)
        for point in [BackupRestoreFailurePoint.afterPreparedWrite, .beforeGenerationInstall] {
            let target = try makeHarness("configuration-clone-recovery-\(point)")
            defer { try? fileManager.removeItem(at: target.root) }
            let validated = try importPackage(draft.package, into: target.session)
            let service = try BackupRestoreService(applicationSupportURL: target.support,
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point))
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(validatedPackage: validated,
                    currentModelContext: target.session.modelContext,
                    currentGenerationID: target.session.generationID,
                    currentGenerationRootURL: target.session.generationRootURL, mode: .clone)
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
            }
            let intents = try RestoreIntentStore(applicationSupportURL: target.support)
            let intent = try XCTUnwrap(intents.load())
            XCTAssertEqual(intent.phase, .prepared)
            XCTAssertFalse(fileManager.fileExists(atPath: configurationCloneDraftRoot(target.support).path))
            let binding = target.support.appendingPathComponent(
                "FieldEvidenceRestore/draft-publication-\(intent.restoreID.uuidString.lowercased()).json")
            XCTAssertFalse(fileManager.fileExists(atPath: binding.path))
            let recovery = try BackupRestoreService(applicationSupportURL: target.support)
            let result = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            XCTAssertNil(result)
            XCTAssertNil(try intents.load())
            XCTAssertEqual(try target.factory.currentGenerationID(), target.session.generationID)
            try assertNoConfigurationCloneDraftRows(in: target.session.modelContext)
            XCTAssertFalse(fileManager.fileExists(atPath: configurationCloneDraftRoot(target.support).path))
            XCTAssertFalse(fileManager.fileExists(atPath: binding.path))
            XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
            try await assertConfigurationCloneDraftSourceUnchanged(source, draft: draft)
        }
    }
}

private extension S6_4AtomicRestoreTests {
    struct ConfigurationCloneDraftPackage {
        let package: URL
        let checkpoint: FieldDraftCheckpointV1
        let item: AttachmentStagingItemV1
        let bytes: Data
    }

    @MainActor
    func makeConfigurationCloneDraftPackage(in source: Harness) async throws -> ConfigurationCloneDraftPackage {
        let coordinator = try StoreSessionCoordinator(validatingSession: source.session)
        defer { try? coordinator.invalidateAndReleaseWriter() }
        let workspace = coordinator.workspaceID
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try C36FieldDraftTestSupportV1.makeFixture()
        let staging = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: source.support, workspaceID: workspace, clock: { date })
        let bytes = Data("nonempty user draft bytes preserved at the clone boundary".utf8)
        let item = try await staging.stage(data: bytes, draftID: UUID(),
            workspaceID: workspace, attachmentKind: .file)
        let checkpoint = try FieldDraftCheckpointV1(
            draftID: item.draftID, workspaceID: workspace,
            scope: fixture.activeCheckpoint.scope, purpose: fixture.activeCheckpoint.purpose,
            codec: fixture.activeCheckpoint.codec, baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: fixture.activeCheckpoint.payloadData, stageIDs: [item.stageID],
            resumeAnchor: fixture.activeCheckpoint.resumeAnchor, state: .active,
            updatedAt: date, mutationID: MutationIDV1(rawValue: UUID()))
        for payload in [FieldDraftMutationPayloadV1.createCheckpoint(checkpoint), .appendStagingItem(item)] {
            let mutation = try FieldDraftMutationV1(workspaceID: workspace, expectedRevision: 0,
                expectedBaseCanonicalRevision: 0, mutationID: payload.mutationID, postImage: payload)
            let receipt = try coordinator.workspaceWriter.execute(
                .applyFieldDraft(mutation), mutationID: mutation.mutationID)
            XCTAssertEqual(receipt.mutationID, mutation.mutationID)
        }
        let destination = source.root.appendingPathComponent("configuration-clone-export")
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let exporter = BackupExportService(modelContext: source.session.modelContext,
            generationRootURL: source.session.generationRootURL, now: { date.addingTimeInterval(60) })
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: destination)
        return .init(package: package, checkpoint: checkpoint, item: item, bytes: bytes)
    }

    func assertConfigurationCloneStockDestinationPolicy(
        source: V4BackupRecordsV1, projected: V4BackupRecordsV1,
        identity: RestoreIdentityV1
    ) throws {
        XCTAssertEqual(identity.mode, .clone)
        XCTAssertNotEqual(identity.source.workspaceID, identity.targetPointer.workspaceID)
        XCTAssertEqual(try XCTUnwrap(source.partsStockSnapshot).workspaceID.rawValue,
            identity.source.workspaceID)
        XCTAssertEqual(try XCTUnwrap(projected.partsStockSnapshot).workspaceID.rawValue,
            identity.targetPointer.workspaceID)
        // C52/C53 history remains source-bound; only stock is destination-bound.
        try C53ServiceReliabilityBackupEnrollmentV1.validate(
            records: projected, workspaceID: identity.source.workspaceID)
        for mode in [BackupRestoreMode.clone, .fork] {
            let policyIdentity = RestoreIdentityV1(mode: mode, source: identity.source,
                oldPointer: identity.oldPointer, targetPointer: identity.targetPointer,
                recordIdentityDisposition: identity.recordIdentityDisposition)
            XCTAssertNoThrow(try C52ServiceRequestRestoreIdentityPolicyV1.validate(
                projected, identity: policyIdentity))
            for foreignStock in [true, false] {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(projected)) as? [String: Any])
                if foreignStock {
                    object["partsStockSnapshot"] = try JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(try XCTUnwrap(source.partsStockSnapshot)))
                } else {
                    object.removeValue(forKey: "partsStockSnapshot")
                }
                let hostile = try JSONDecoder().decode(V4BackupRecordsV1.self,
                    from: JSONSerialization.data(withJSONObject: object))
                XCTAssertThrowsError(try C52ServiceRequestRestoreIdentityPolicyV1.validate(
                    hostile, identity: policyIdentity)) {
                    XCTAssertEqual($0 as? RestoreIdentityDecisionErrorV1, .invalidPointerIdentity)
                }
            }
        }
    }

    @MainActor
    func assertNoConfigurationCloneDraftRows(in context: ModelContext) throws {
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DraftContentReservationRow>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DraftCommitReceiptRow>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()), 0)
    }

    func configurationCloneDraftRoot(_ support: URL) -> URL {
        support.appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
            .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName, isDirectory: true)
    }

    @MainActor
    func assertConfigurationCloneDraftSourceUnchanged(_ source: Harness,
        draft: ConfigurationCloneDraftPackage) async throws {
        let checkpoints = try source.session.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
        let items = try source.session.modelContext.fetch(FetchDescriptor<AttachmentStagingItemRow>())
        XCTAssertEqual(try checkpoints.map { try $0.value() }, [draft.checkpoint])
        XCTAssertEqual(try items.map { try $0.value() }, [draft.item])
        let staging = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: source.support, workspaceID: source.session.workspaceID)
        let bytes = try await staging.data(stageID: draft.item.stageID)
        XCTAssertEqual(bytes, draft.bytes)
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testConfigurationCloneRetirementOldPointerRollbackRestoresExactIncumbent() async throws {
        for step in ["after-retirement-plan", "after-retirement-intent", "after-retirement-ownership",
                     "after-moved-root", "after-replacement-quarantine", "after-empty-manifest"] {
            let fixture = try await makeCloneRetirementFixture("old-\(step)")
            try await interruptCloneRetirement(fixture, at: step)
            XCTAssertEqual(try fixture.harness.factory.currentGenerationID(), fixture.harness.session.generationID, step)
            let recovery = try BackupRestoreService(applicationSupportURL: fixture.harness.support)
            XCTAssertNil(try recovery.reconcileAtStartup(), step)
            let completed = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            XCTAssertNil(completed, step)
            try await assertCloneRetirementRolledBack(fixture, label: step)
        }
    }

    @MainActor
    func testConfigurationCloneRetirementPointerLagAndPrivateCleanupResume() async throws {
        for step in ["after-retirement-pointer", "after-retirement-generation-retired", "after-retire-claim",
                     "after-retire-delete", "after-scaffold-delete"] {
            let fixture = try await makeCloneRetirementFixture("new-\(step)")
            try await interruptCloneRetirement(fixture, at: step)
            let intents = try RestoreIntentStore(applicationSupportURL: fixture.harness.support)
            let interrupted = try XCTUnwrap(intents.load(), step)
            XCTAssertEqual(try fixture.harness.factory.currentGenerationID(), fixture.newGenerationID, step)
            if step == "after-retirement-pointer" {
                XCTAssertEqual(interrupted.phase, .generationInstalled)
                XCTAssertFalse(try fixture.harness.factory.retiredGenerationIDs().contains(fixture.harness.session.generationID))
            } else {
                XCTAssertEqual(interrupted.phase, .newGenerationValidated)
                XCTAssertTrue(try fixture.harness.factory.retiredGenerationIDs().contains(fixture.harness.session.generationID))
            }
            let recovery = try BackupRestoreService(applicationSupportURL: fixture.harness.support)
            let synchronous = try XCTUnwrap(recovery.reconcileAtStartup(), step)
            XCTAssertEqual(synchronous.generationID, fixture.newGenerationID, step)
            XCTAssertEqual(try intents.load()?.phase, .newGenerationValidated, step)
            let completed = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            XCTAssertEqual(completed?.generationID, fixture.newGenerationID, step)
            try assertCloneRetirementFinished(fixture, label: step)
        }
    }

    @MainActor
    func testConfigurationCloneRetirementTerminalMetadataResumesWithoutBaseIntent() async throws {
        for step in ["after-retirement-terminal-binding", "after-retirement-intent-removal",
                     "after-retirement-sidecar-removal"] {
            let fixture = try await makeCloneRetirementFixture("metadata-\(step)")
            try await interruptCloneRetirement(fixture, at: step)
            let intents = try RestoreIntentStore(applicationSupportURL: fixture.harness.support)
            if step == "after-retirement-terminal-binding" {
                XCTAssertEqual(try intents.load()?.phase, .newGenerationValidated)
            } else { XCTAssertNil(try intents.load()) }
            XCTAssertEqual(fileManager.fileExists(atPath: cloneRetirementBindingURL(fixture).path),
                step != "after-retirement-sidecar-removal", step)
            let recovery = try BackupRestoreService(applicationSupportURL: fixture.harness.support)
            _ = try recovery.reconcileAtStartup()
            _ = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            try assertCloneRetirementFinished(fixture, label: step)
        }
    }

    @MainActor
    func testConfigurationCloneRetirementRollbackInterruptionsResume() async throws {
        for step in ["after-rollback-manifest", "after-restored-root", "after-scaffold-delete",
                     "after-retirement-rollback-binding"] {
            let fixture = try await makeCloneRetirementFixture("rollback-\(step)")
            try await interruptCloneRetirement(fixture, at: "after-empty-manifest")
            let recovery = try BackupRestoreService(applicationSupportURL: fixture.harness.support)
            var reached = false
            recovery.configurationCloneRetirementObservationForTesting = { label in
                if label == step && !reached { reached = true; throw BackupRestoreServiceError.injectedFailure }
            }
            XCTAssertThrowsError(try recovery.reconcileAtStartup(), step) {
                XCTAssertEqual($0 as? BackupRestoreServiceError, .injectedFailure, step)
            }
            XCTAssertTrue(reached, step)
            XCTAssertEqual(try fixture.harness.factory.currentGenerationID(), fixture.harness.session.generationID, step)
            XCTAssertNotNil(try RestoreIntentStore(applicationSupportURL: fixture.harness.support).load(), step)
            let reopened = try BackupRestoreService(applicationSupportURL: fixture.harness.support)
            let completed = try await reopened.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            XCTAssertNil(completed, step)
            try await assertCloneRetirementRolledBack(fixture, label: step)
        }
    }

    @MainActor
    func testConfigurationCloneRetirementUnclaimedScaffoldAndBindingTamperFailClosed() async throws {
        for scenario in ["unclaimed", "missing", "wrong-digest", "unknown-key"] {
            let fixture = try await makeCloneRetirementFixture("authority-\(scenario)")
            try await interruptCloneRetirement(fixture,
                at: scenario == "unclaimed" ? "after-retirement-scaffold" : "after-retirement-ownership")
            let bindingURL = cloneRetirementBindingURL(fixture)
            if scenario == "missing" {
                try fileManager.removeItem(at: bindingURL)
            } else if scenario != "unclaimed" {
                var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bindingURL)) as? [String: Any])
                if scenario == "unknown-key" { value["unownedCleanup"] = true }
                else {
                    var core = try XCTUnwrap(value["core"] as? [String: Any])
                    core["currentRecordsSHA256"] = String(repeating: "f", count: 64)
                    value["core"] = core
                }
                try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
                    .write(to: bindingURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: bindingURL)
            }
            XCTAssertTrue(fileManager.fileExists(atPath: cloneRetirementPrivateRoot(fixture).path), scenario)
            try await assertCloneRetirementRecoveryDeniesWithoutEffects(fixture, label: scenario)
        }
    }

    @MainActor
    func testConfigurationCloneRetirementChangedPrivateBytesAndUnknownNodesRemainUntouched() async throws {
        for switched in [false, true] {
            for scenario in ["changed", "missing", "unknown"] {
                let fixture = try await makeCloneRetirementFixture("private-\(switched)-\(scenario)")
                try await interruptCloneRetirement(fixture, at: switched ? "after-retirement-pointer" : "after-empty-manifest")
                let root = cloneRetirementPrivateRoot(fixture)
                let payload = root.appendingPathComponent(DraftAttachmentStagingAdapterV1.relativeDataPath(
                    draftID: fixture.draft.item.draftID, stageID: fixture.draft.item.stageID))
                if scenario == "missing" { try fileManager.removeItem(at: payload) }
                else {
                    let target = scenario == "unknown" ? root.appendingPathComponent("unclaimed-user-bytes.bin") : payload
                    try Data("changed bytes have no retirement authority".utf8).write(to: target, options: .atomic)
                    try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: target)
                }
                try await assertCloneRetirementRecoveryDeniesWithoutEffects(fixture,
                    label: "\(switched)-\(scenario)")
            }
        }
    }

    @MainActor
    func testConfigurationCloneRetirementAccessAndCancellationRetainRecoveryOwner() async throws {
        for boundary in [ConfigurationCloneRestoreObservationPointV1.afterFinalMediaCopy, .afterFinalCleanup] {
            for cancel in [false, true] {
                let fixture = try await makeCloneRetirementFixture("access-\(boundary)-\(cancel)")
                let service = try BackupRestoreService(applicationSupportURL: fixture.harness.support,
                    makeUUID: sequence([fixture.newGenerationID, fixture.restoreID]))
                var reached = false, allowed = true
                service.configurationCloneObservationForTesting = { point in
                    guard point == boundary else { return }
                    reached = true
                    if cancel { withUnsafeCurrentTask { $0?.cancel() } }
                    else { allowed = false }
                }
                let operation = Task { @MainActor in
                    try await service.restore(validatedPackage: fixture.package,
                        currentModelContext: fixture.harness.session.modelContext,
                        currentGenerationID: fixture.harness.session.generationID,
                        currentGenerationRootURL: fixture.harness.session.generationRootURL,
                        mode: .clone, validateAccess: {
                            if !allowed { throw FixtureError.publicationDenied }
                        })
                }
                await XCTAssertThrowsErrorAsync { _ = try await operation.value } verify: { error in
                    if cancel { XCTAssertTrue(error is CancellationError) }
                    else {
                        guard let fixtureError = error as? FixtureError,
                              case .publicationDenied = fixtureError else {
                            return XCTFail("Expected publicationDenied, got \(error)")
                        }
                    }
                }
                XCTAssertTrue(reached)
                let intents = try RestoreIntentStore(applicationSupportURL: fixture.harness.support)
                if boundary == .afterFinalMediaCopy {
                    XCTAssertNil(try intents.load())
                    XCTAssertFalse(fileManager.fileExists(atPath: cloneRetirementBindingURL(fixture).path))
                    XCTAssertEqual(try configurationCloneRetirementTree(configurationCloneDraftRoot(fixture.harness.support)), fixture.stagingBefore)
                    XCTAssertEqual(try fixture.harness.factory.currentGenerationID(), fixture.harness.session.generationID)
                } else {
                    XCTAssertEqual(try intents.load()?.phase, .newGenerationValidated)
                    XCTAssertTrue(fileManager.fileExists(atPath: cloneRetirementBindingURL(fixture).path))
                    XCTAssertTrue(fileManager.fileExists(atPath: cloneRetirementPrivateRoot(fixture).path))
                    XCTAssertEqual(try fixture.harness.factory.currentGenerationID(), fixture.newGenerationID)
                    let recovery = try BackupRestoreService(applicationSupportURL: fixture.harness.support)
                    _ = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
                    try assertCloneRetirementFinished(fixture, label: "access-recovery")
                }
                try assertCloneRetirementOldCanonicalUnchanged(fixture)
            }
        }
    }

    @MainActor
    func testConfigurationCloneRetirementClaimRejectsAnInodeSubstitution() async throws {
        let fixture = try await makeCloneRetirementFixture("claim-substitution")
        let service = try BackupRestoreService(applicationSupportURL: fixture.harness.support,
            makeUUID: sequence([fixture.newGenerationID, fixture.restoreID]))
        var substituted: URL?
        let hostile = Data("replacement belongs to no retirement claim".utf8)
        service.configurationCloneRetirementBeforeClaimForTesting = { url, directory in
            guard !directory, url.lastPathComponent == "payload.bin", substituted == nil else { return }
            try hostile.write(to: url, options: .atomic)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: url)
            substituted = url
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(validatedPackage: fixture.package,
                currentModelContext: fixture.harness.session.modelContext,
                currentGenerationID: fixture.harness.session.generationID,
                currentGenerationRootURL: fixture.harness.session.generationRootURL, mode: .clone)
        } verify: { _ in }
        let retained = try XCTUnwrap(substituted)
        XCTAssertEqual(try Data(contentsOf: retained), hostile)
        XCTAssertEqual(try fixture.harness.factory.currentGenerationID(), fixture.newGenerationID)
        XCTAssertEqual(try RestoreIntentStore(applicationSupportURL: fixture.harness.support).load()?.phase, .newGenerationValidated)
        try await assertCloneRetirementRecoveryDeniesWithoutEffects(fixture, label: "substituted-inode")
        XCTAssertEqual(try Data(contentsOf: retained), hostile)
    }
}

private extension S6_4AtomicRestoreTests {
    struct CloneRetirementFixture {
        let harness: Harness
        let draft: ConfigurationCloneDraftPackage
        let package: ValidatedV4BackupPackageV1
        let newGenerationID: UUID
        let restoreID: UUID
        let oldCanonical: Data
        let destinationCanonical: Data
        let pointerBefore: Data
        let stagingBefore: [FileFact]
        let payloadIdentity: StreamingArchiveRootIdentityV1
        let archiveBefore: Data
    }

    @MainActor
    func makeCloneRetirementFixture(_ label: String) async throws -> CloneRetirementFixture {
        let harness = try makeHarness("retirement-\(label)")
        // XCTest runs this after the case's live model/lease owners leave scope.
        let root = harness.root
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let draft = try await makeConfigurationCloneDraftPackage(in: harness)
        let package = try importPackage(draft.package, into: harness.session)
        let inspector = try BackupRestoreService(applicationSupportURL: harness.support)
        let records = try inspector.c55CurrentRecordsForTesting(in: harness.session.modelContext)
        // This is a genuine export of the incumbent workspace. Clone must
        // validate against its newly allocated destination, not the incumbent.
        XCTAssertEqual(package.manifest.source.workspaceID, harness.session.workspaceID.rawValue)
        XCTAssertThrowsError(try C53ServiceReliabilityReplacementRestoreBoundaryV1.validate(
            current: records, incoming: package.records, mode: .clone,
            sourceWorkspaceID: package.manifest.source.workspaceID,
            targetWorkspaceID: harness.session.workspaceID.rawValue)) {
            XCTAssertEqual($0 as? ReplacementRestoreRuleError, .invalidAuthority)
        }
        let oldCanonical = try BackupCanonicalEncoderV1().encodeRecords(records).data
        // The actual clone path replaces C22 assessments before encoding its
        // destination. Every unrelated modern snapshot must survive that copy.
        let copied = records.replacingAccessibleDocumentAssessments(records.accessibleDocumentAssessments)
        XCTAssertEqual(copied, records)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(copied).data, oldCanonical)
        try assertRestoreRecordCopyPipelinePreservesOriginals(records,
            identity: harness.factory.currentWorkspaceIdentity(expectedGenerationID: harness.session.generationID),
            expectedCanonical: oldCanonical)
        try assertAssessmentCopyPreservesRejectedServiceHistory(records, workspaceID: harness.session.workspaceID.rawValue)
        let destinationCanonical = try BackupCanonicalEncoderV1()
            .encodeRecords(package.records).data
        // The incumbent reader uses its minimal historical envelope. The real
        // export supplies the current envelope and its mandatory C12 snapshot.
        XCTAssertGreaterThanOrEqual(package.records.recordsSchemaVersion,
            ReinspectionExceptionQueueBackupEnrollmentV1.recordsSchemaVersion)
        XCTAssertNotNil(package.records.reinspectionExceptionQueue)
        try assertRestoreRecordCopyPipelinePreservesOriginals(package.records,
            identity: harness.factory.currentWorkspaceIdentity(expectedGenerationID: harness.session.generationID),
            expectedCanonical: destinationCanonical)
        let payload = configurationCloneDraftRoot(harness.support).appendingPathComponent(
            DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: draft.item.draftID, stageID: draft.item.stageID))
        return .init(harness: harness, draft: draft, package: package,
            newGenerationID: UUID(), restoreID: UUID(), oldCanonical: oldCanonical,
            destinationCanonical: destinationCanonical,
            pointerBefore: try Data(contentsOf: harness.support.appendingPathComponent("FieldEvidenceData/current.json")),
            stagingBefore: try configurationCloneRetirementTree(configurationCloneDraftRoot(harness.support)),
            payloadIdentity: try cloneRetirementFileIdentity(payload),
            archiveBefore: try Data(contentsOf: draft.package))
    }

    // Nonempty hostile transport rows are intentionally not accepted C53
    // evidence. A value copy must retain them so the existing owner still
    // rejects them, rather than silently producing empty valid history.
    func assertAssessmentCopyPreservesRejectedServiceHistory(_ records: V4BackupRecordsV1,
        workspaceID: UUID) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(records)) as? [String: Any])
        let families: [(String, V39BackupServiceReliabilityRecordV1.Kind)] = [
            ("serviceReliabilityIncidents", .incident), ("serviceImpactSegments", .impactSegment),
            ("serviceCauseAssertions", .causeAssertion), ("serviceRemedyAssertions", .remedyAssertion),
            ("serviceRepairIntervals", .repairInterval), ("serviceRestorationAssertions", .restorationAssertion),
            ("qualifiedServiceExposures", .qualifiedExposure),
        ]
        for (key, kind) in families {
            let row = try V39BackupServiceReliabilityRecordV1(kind: kind,
                eventID: UUID(), lineageID: UUID(), incidentID: UUID(),
                workspaceID: workspaceID, revision: 1, mutationID: UUID(),
                eventSHA256: String(repeating: "a", count: 64), canonicalData: Data("invalid C53 body".utf8))
            object[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([row]))
        }
        object["serviceReliabilityReceipts"] = [[
            "mutationID": UUID().uuidString, "bundleSHA256": String(repeating: "b", count: 64),
            "canonicalData": Data("invalid C53 receipt".utf8).base64EncodedString(),
        ]]
        let hostile = try JSONDecoder().decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        XCTAssertThrowsError(try C53ServiceReliabilityBackupEnrollmentV1.validate(
            records: hostile, workspaceID: workspaceID))
        let copies = [
            hostile.replacingAccessibleDocumentAssessments(hostile.accessibleDocumentAssessments),
            hostile.replacingOperationalContacts(hostile.operationalContacts),
            hostile.replacingEvidenceMetadata(hostile.evidenceAssociationEvents, hostile.evidenceSequenceRevisions),
        ]
        for copied in copies {
            XCTAssertEqual(copied, hostile)
            XCTAssertThrowsError(try C53ServiceReliabilityBackupEnrollmentV1.validate(
                records: copied, workspaceID: workspaceID))
        }
    }

    func assertRestoreRecordCopyPipelinePreservesOriginals(_ records: V4BackupRecordsV1,
        identity: WorkspaceReplicaIdentityV1, expectedCanonical: Data) throws {
        let reliability = try C53ServiceReliabilityBackupEnrollmentV1.canonicalRows(
            from: records, workspaceID: identity.workspaceID.rawValue)
        let copies = try [
            records.replacingOperationalContacts(records.operationalContacts),
            records.replacingEvidenceMetadata(records.evidenceAssociationEvents, records.evidenceSequenceRevisions),
            records.replacingServiceReliability(reliability),
        ]
        for copied in copies {
            XCTAssertEqual(copied, records)
            XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(copied).data, expectedCanonical)
        }
        // Exercise the earlier loss too: forwarding a snapshot in the last
        // copier cannot recover one discarded by deletion-winning projection.
        for mode in [BackupRestoreMode.clone, .replaceExisting] {
            let projected = try ReplacementRestoreRule.makeDeletionWinningPlan(.init(
                currentRecords: records, currentIdentity: identity, incomingRecords: records, incomingIdentity: identity,
                mode: mode, replacementAt: Date(timeIntervalSince1970: 1_800_000_000))).recordsAfter
            let contacts = projected.replacingOperationalContacts(records.operationalContacts)
            let service = try contacts.replacingServiceReliability(reliability)
            let metadata = service.replacingEvidenceMetadata(records.evidenceAssociationEvents, records.evidenceSequenceRevisions)
            let copied = metadata.replacingAccessibleDocumentAssessments(metadata.accessibleDocumentAssessments)
            XCTAssertEqual(copied, records)
            XCTAssertEqual(copied.reinspectionExceptionQueue, records.reinspectionExceptionQueue)
            XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(copied).data, expectedCanonical)
        }
    }

    @MainActor
    func interruptCloneRetirement(_ fixture: CloneRetirementFixture, at step: String) async throws {
        let service = try BackupRestoreService(applicationSupportURL: fixture.harness.support,
            makeUUID: sequence([fixture.newGenerationID, fixture.restoreID]))
        var reached = false
        service.configurationCloneRetirementObservationForTesting = { label in
            guard label == step, !reached else { return }
            reached = true
            throw BackupRestoreServiceError.injectedFailure
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(validatedPackage: fixture.package,
                currentModelContext: fixture.harness.session.modelContext,
                currentGenerationID: fixture.harness.session.generationID,
                currentGenerationRootURL: fixture.harness.session.generationRootURL, mode: .clone)
        } verify: {
            XCTAssertEqual($0 as? BackupRestoreServiceError, .injectedFailure,
                "\(step); actual error: \(String(reflecting: $0))")
        }
        XCTAssertTrue(reached, "Must reach the actual durable step: \(step)")
        if let intent = try RestoreIntentStore(applicationSupportURL: fixture.harness.support).load() {
            XCTAssertEqual(intent.restoreID, fixture.restoreID, step)
            XCTAssertEqual(intent.schemaVersion, 4, step)
            XCTAssertNotNil(intent.cloneRetirementPlanSHA256, step)
        }
        try assertCloneRetirementOldCanonicalUnchanged(fixture)
    }

    @MainActor
    func assertCloneRetirementOldCanonicalUnchanged(_ fixture: CloneRetirementFixture) throws {
        let inspector = try BackupRestoreService(applicationSupportURL: fixture.harness.support)
        let records = try inspector.c55CurrentRecordsForTesting(in: fixture.harness.session.modelContext)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(records).data, fixture.oldCanonical)
        XCTAssertEqual(try Data(contentsOf: fixture.draft.package), fixture.archiveBefore)
        XCTAssertEqual(try fixture.harness.session.modelContext.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()), 0)
    }

    @MainActor
    func assertCloneRetirementRolledBack(_ fixture: CloneRetirementFixture, label: String) async throws {
        XCTAssertEqual(try fixture.harness.factory.currentGenerationID(), fixture.harness.session.generationID, label)
        XCTAssertTrue(try fixture.harness.factory.retiredGenerationIDs().isEmpty, label)
        XCTAssertEqual(try Data(contentsOf: fixture.harness.support.appendingPathComponent("FieldEvidenceData/current.json")), fixture.pointerBefore, label)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: fixture.harness.support).load(), label)
        XCTAssertFalse(fileManager.fileExists(atPath: cloneRetirementBindingURL(fixture).path), label)
        XCTAssertFalse(fileManager.fileExists(atPath: cloneRetirementPrivateRoot(fixture).path), label)
        XCTAssertEqual(try configurationCloneRetirementTree(configurationCloneDraftRoot(fixture.harness.support)), fixture.stagingBefore, label)
        let payload = configurationCloneDraftRoot(fixture.harness.support).appendingPathComponent(
            DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: fixture.draft.item.draftID, stageID: fixture.draft.item.stageID))
        XCTAssertEqual(try cloneRetirementFileIdentity(payload), fixture.payloadIdentity, label)
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.harness.factory.installedGenerationURL(id: fixture.newGenerationID).path), label)
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.harness.factory.restoreStagingGenerationURL(id: fixture.newGenerationID).path), label)
        try await assertConfigurationCloneDraftSourceUnchanged(fixture.harness, draft: fixture.draft)
        try assertCloneRetirementOldCanonicalUnchanged(fixture)
    }

    @MainActor
    func assertCloneRetirementFinished(_ fixture: CloneRetirementFixture, label: String) throws {
        XCTAssertEqual(try fixture.harness.factory.currentGenerationID(), fixture.newGenerationID, label)
        XCTAssertTrue(try fixture.harness.factory.retiredGenerationIDs().contains(fixture.harness.session.generationID), label)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: fixture.harness.support).load(), label)
        XCTAssertFalse(fileManager.fileExists(atPath: cloneRetirementBindingURL(fixture).path), label)
        XCTAssertFalse(fileManager.fileExists(atPath: cloneRetirementPrivateRoot(fixture).path), label)
        let root = configurationCloneDraftRoot(fixture.harness.support)
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: root.path)), ["manifest.json", "quarantine"], label)
        XCTAssertTrue(try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent("quarantine").path).isEmpty, label)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("manifest.json")),
            try DraftAttachmentStagingManifestV1(entries: []).canonicalBytes(), label)
        let destination = try fixture.harness.factory.openOrBootstrapCurrent()
        XCTAssertNotEqual(destination.workspaceID, fixture.harness.session.workspaceID, label)
        try assertNoConfigurationCloneDraftRows(in: destination.modelContext)
        let inspector = try BackupRestoreService(
            applicationSupportURL: fixture.harness.support
        )
        let records = try inspector.c55CurrentRecordsForTesting(
            in: destination.modelContext
        )
        XCTAssertEqual(
            try BackupCanonicalEncoderV1().encodeRecords(records).data,
            fixture.destinationCanonical,
            label
        )
        try assertCloneRetirementOldCanonicalUnchanged(fixture)
    }

    @MainActor
    func assertCloneRetirementRecoveryDeniesWithoutEffects(_ fixture: CloneRetirementFixture, label: String) async throws {
        let intents = try RestoreIntentStore(applicationSupportURL: fixture.harness.support)
        let beforeIntent = try intents.load()
        let pointerURL = fixture.harness.support.appendingPathComponent("FieldEvidenceData/current.json")
        let beforePointer = try Data(contentsOf: pointerURL)
        let beforeRetired = try fixture.harness.factory.retiredGenerationIDs()
        let stageBefore = try configurationCloneRetirementTree(configurationCloneDraftRoot(fixture.harness.support))
        let metadataBefore = try cloneRetirementMetadata(fixture)
        let recovery = try BackupRestoreService(applicationSupportURL: fixture.harness.support)
        XCTAssertThrowsError(try recovery.reconcileAtStartup(), label)
        await XCTAssertThrowsErrorAsync { _ = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup() } verify: { _ in }
        XCTAssertEqual(try intents.load(), beforeIntent, label)
        XCTAssertEqual(try Data(contentsOf: pointerURL), beforePointer, label)
        XCTAssertEqual(try fixture.harness.factory.retiredGenerationIDs(), beforeRetired, label)
        XCTAssertEqual(try configurationCloneRetirementTree(configurationCloneDraftRoot(fixture.harness.support)), stageBefore, label)
        XCTAssertEqual(try cloneRetirementMetadata(fixture), metadataBefore, label)
        try assertCloneRetirementOldCanonicalUnchanged(fixture)
    }

    func cloneRetirementBindingURL(_ fixture: CloneRetirementFixture) -> URL {
        fixture.harness.support.appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent("clone-retirement-\(fixture.restoreID.uuidString.lowercased()).json")
    }

    func cloneRetirementPrivateRoot(_ fixture: CloneRetirementFixture) -> URL {
        configurationCloneDraftRoot(fixture.harness.support)
            .appendingPathComponent(".clone-retirement-\(fixture.restoreID.uuidString.lowercased())", isDirectory: true)
    }

    func cloneRetirementMetadata(_ fixture: CloneRetirementFixture) throws -> [FileFact] {
        let current = cloneRetirementBindingURL(fixture)
        let next = current.deletingLastPathComponent().appendingPathComponent(".\(current.lastPathComponent).next")
        return try [current, next].compactMap { url in
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return FileFact(path: url.lastPathComponent, bytes: try Data(contentsOf: url))
        }
    }

    func cloneRetirementFileIdentity(_ url: URL) throws -> StreamingArchiveRootIdentityV1 {
        var value = stat()
        guard Darwin.lstat(url.path, &value) == 0, (value.st_mode & S_IFMT) == S_IFREG, value.st_nlink == 1 else {
            throw FixtureError.invalid
        }
        return .init(device: UInt64(value.st_dev), inode: UInt64(value.st_ino))
    }

    func configurationCloneRetirementTree(_ root: URL) throws -> [FileFact] {
        guard let values = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            throw FixtureError.invalid
        }
        var result: [FileFact] = []
        for case let url as URL in values {
            let directory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            let path = String(url.path.dropFirst(root.path.count + 1))
            result.append(.init(path: path + (directory ? "/" : ""), bytes: directory ? Data() : try Data(contentsOf: url)))
        }
        return result.sorted { $0.path < $1.path }
    }
}
