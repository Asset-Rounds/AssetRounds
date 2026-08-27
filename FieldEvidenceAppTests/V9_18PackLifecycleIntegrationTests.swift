import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V9_18PackLifecycleIntegrationTests: XCTestCase {
    func testV23P03C39WorkflowBindingKeepsEndedDispositionTyped() throws {
        let event = try AssetWorkflowCapabilityBindingEventV1(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000002401")!,
            workspaceID: WorkspaceID(),
            assetID: UUID(uuidString: "00000000-0000-0000-0000-000000002402")!,
            kindBindingEventID: UUID(uuidString: "00000000-0000-0000-0000-000000002403")!,
            kindBindingRevision: 1,
            workflowPackageRelease: try PackageReleaseIdentityV1(
                packageID: "com.field-evidence.c39",
                schemaVersion: 1,
                contentVersion: 1
            ),
            capabilityIDs: [try AssetSemanticCapabilityIDV1("capability.inspect")],
            disposition: .ended,
            predecessorEventID: nil,
            revision: 1,
            mutationID: try MutationIDV1(rawValue: UUID()),
            recordedAt: Date(timeIntervalSince1970: 1_735_689_600),
            eventSHA256: String(repeating: "a", count: 64)
        )
        try event.validate()
        XCTAssertEqual(event.disposition, .ended)
    }

    private let fileManager = FileManager.default

    @MainActor
    func testV9_18G01ShippingLifecycleParityUsesOneClosedProfile() throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let package = SignPack.illuminatedSignV1

        XCTAssertEqual(profile.release, try PackageReleaseIdentityV1(package: package))
        XCTAssertEqual(profile.package, package)
        XCTAssertEqual(profile.stages.map(\.stageKey), ["check", "recheck", "work"])
        assertPackageOutcomeParity(profile: profile, package: package)
        XCTAssertEqual(
            profile.evidencePurposes.map(\.key),
            package.evidencePurposes.map(\.key)
        )
        XCTAssertEqual(
            profile.requiredAcknowledgementKeys,
            package.acknowledgements.map(\.key)
        )
        XCTAssertEqual(profile.pdfTemplate.id, "field.evidence.pdf.worklight.v1")
        XCTAssertEqual(profile.pdfTemplate.version, 1)
        XCTAssertEqual(
            WorkspacePackageLifecycleCompatibilityV1.expiration,
            PackFinalizationAdapterV1.expiresAfter
        )
    }

    @MainActor
    func testV9_18A01AlternatePackageFlowsThroughProductionDependencies() async throws {
        let package = try alternatePackage()
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: package
        )
        let harness = try makeHarness("alternate", profile: profile)
        defer { harness.cleanup(fileManager: fileManager) }

        let runner = try CheckRunnerCoordinator(
            modelContext: harness.session.modelContext,
            packageLifecycleDependencies: harness.dependencies,
            packageLifecycleProfile: profile
        )
        runner.configureCapture(generationRootURL: harness.session.generationRootURL)

        XCTAssertEqual(profile.release.packageID, "test.field.evidence.alternate.v1")
        XCTAssertEqual(profile.package.nouns.asset.singular, "test fixture")
        XCTAssertEqual(profile.stages.map(\.stageKey), ["check", "recheck"])
        XCTAssertEqual(profile.stages.flatMap(\.outcomes).map(\.role).contains(.workRecorded), false)
        assertPackageOutcomeParity(profile: profile, package: package)
        XCTAssertEqual(
            profile.evidencePurposes.map(\.key),
            package.evidencePurposes.map(\.key)
        )
        XCTAssertEqual(
            try harness.dependencies.profileRegistry.resolve(profile.release),
            profile
        )
        let recoveryAdapter = try PackFinalizationRecoveryAdapterV1(
            dependencies: harness.dependencies,
            profile: profile,
            legacyModelContext: harness.session.modelContext
        )
        let recovery = try await recoveryAdapter.reconcile()
        XCTAssertEqual(recovery.packageRelease, profile.release)
        XCTAssertTrue(recovery.summary.recoveredDraftRecordIDs.isEmpty)
        XCTAssertFalse(recovery.zeroFeatureWriteClosureClaimed)
        withExtendedLifetime(runner) {}
    }

    @MainActor
    func testV9_18H01HardcodedReleaseAndForeignDependencyFailClosed() throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let first = try makeHarness("hostile-first", profile: profile)
        let second = try makeHarness("hostile-second", profile: profile)
        defer {
            first.cleanup(fileManager: fileManager)
            second.cleanup(fileManager: fileManager)
        }

        let unknownRelease = try PackageReleaseIdentityV1(
            packageID: "field.evidence.hardcoded.unknown",
            schemaVersion: 1,
            contentVersion: 1
        )
        XCTAssertThrowsError(
            try first.dependencies.profileRegistry.resolve(unknownRelease)
        )

        let foreignRequest = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: second.dependencies.workspaceID,
            generationID: second.dependencies.generationID,
            operation: .query,
            identities: []
        )
        XCTAssertThrowsError(try first.dependencies.queryClient.query(foreignRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWorkspace)
        }

        let wrongGenerationRequest = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: first.dependencies.workspaceID,
            generationID: second.dependencies.generationID,
            operation: .query,
            identities: []
        )
        XCTAssertThrowsError(try first.dependencies.queryClient.query(wrongGenerationRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongGeneration)
        }
    }

    @MainActor
    func testV9_18I01CancellationAndCompetingMutationDoNotCreatePartialAuthority() async throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let harness = try makeHarness("interruption", profile: profile)
        defer { harness.cleanup(fileManager: fileManager) }

        let recovery = try PackFinalizationRecoveryAdapterV1(
            dependencies: harness.dependencies,
            profile: profile,
            legacyModelContext: harness.session.modelContext
        )
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await recovery.reconcile()
        }
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled recovery must fail before discovering or applying authority")
        } catch is CancellationError {
            // Expected fail-closed interruption boundary.
        }

        let firstMutationID = try harness.dependencies.writer.makeMutationID()
        let firstCommand = try makeFirstAssetCommand(
            label: "Primary",
            mutationID: firstMutationID
        )
        let firstOutcome = try harness.dependencies.writer.execute(
            firstCommand,
            mutationID: firstMutationID
        )
        let competingCommand = try makeFirstAssetCommand(
            label: "Competing",
            mutationID: firstOutcome.mutationID
        )
        let competingRequest = try request(
            mutationID: firstOutcome.mutationID,
            command: competingCommand,
            writer: harness.dependencies.writer
        )
        XCTAssertThrowsError(try harness.dependencies.writer.execute(competingRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try harness.dependencies.writer.currentRevision().revision, 1)
    }

    @MainActor
    func testV9_18R01TwoWorkspacesRemainIsolatedAndRecoverIndependently() async throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let first = try makeHarness("recovery-first", profile: profile)
        let second = try makeHarness("recovery-second", profile: profile)
        defer {
            first.cleanup(fileManager: fileManager)
            second.cleanup(fileManager: fileManager)
        }
        XCTAssertNotEqual(first.dependencies.workspaceID, second.dependencies.workspaceID)
        XCTAssertNotEqual(first.dependencies.generationID, second.dependencies.generationID)

        let firstMutationID = try first.dependencies.writer.makeMutationID()
        _ = try first.dependencies.writer.execute(
            try makeFirstAssetCommand(
                label: "First only",
                mutationID: firstMutationID
            ),
            mutationID: firstMutationID
        )
        let firstAsset = try XCTUnwrap(
            try first.session.modelContext.fetch(FetchDescriptor<Asset>()).first
        )
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: firstAsset.id)
        let localRequest = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: first.dependencies.workspaceID,
            generationID: first.dependencies.generationID,
            operation: .query,
            identities: [identity]
        )
        XCTAssertEqual(
            try first.dependencies.queryClient.query(localRequest).existingIdentities,
            [identity]
        )
        XCTAssertThrowsError(try second.dependencies.queryClient.query(localRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWorkspace)
        }
        XCTAssertTrue(try second.session.modelContext.fetch(FetchDescriptor<Asset>()).isEmpty)

        let firstRecovery = try PackFinalizationRecoveryAdapterV1(
            dependencies: first.dependencies,
            profile: profile,
            legacyModelContext: first.session.modelContext
        )
        let secondRecovery = try PackFinalizationRecoveryAdapterV1(
            dependencies: second.dependencies,
            profile: profile,
            legacyModelContext: second.session.modelContext
        )
        let firstOutcome = try await firstRecovery.reconcile()
        let secondOutcome = try await secondRecovery.reconcile()
        XCTAssertEqual(firstOutcome.workspaceID, first.dependencies.workspaceID)
        XCTAssertEqual(secondOutcome.workspaceID, second.dependencies.workspaceID)
        XCTAssertTrue(firstOutcome.summary.recoveredDraftRecordIDs.isEmpty)
        XCTAssertTrue(secondOutcome.summary.completedRecordIDs.isEmpty)
        XCTAssertTrue(firstOutcome.preservesReservedLegacyRawWriteDebt)
        XCTAssertFalse(firstOutcome.zeroFeatureWriteClosureClaimed)
    }

    @MainActor
    private func makeHarness(
        _ label: String,
        profile: WorkspacePackageLifecycleProfileV1
    ) throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_18PackLifecycleIntegrationTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        let session = try StoreGenerationFactory(
            applicationSupportURL: root
        ).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(
            profiles: [profile]
        )
        let dependencies = try coordinator.packageLifecycleDependencies(
            profileRegistry: registry
        )
        return Harness(
            root: root,
            session: session,
            coordinator: coordinator,
            dependencies: dependencies
        )
    }

    private func alternatePackage() throws -> SignPack {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C01AlternatePackV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Packs"
            ) ?? bundle.url(
                forResource: "V21P03C01AlternatePackV1",
                withExtension: "json"
            )
        )
        let raw = try Data(contentsOf: url)
        guard raw.last == 0x0A else { throw TestFailure.invalidFixture }
        let package = try InspectionPackageCanonicalCodecV2.decode(Data(raw.dropLast()))
        let presentation = package.presentation
        return SignPack(
            schemaVersion: package.schemaVersion,
            packID: package.packageID,
            contentVersion: package.contentVersion,
            nouns: .init(
                asset: .init(
                    singular: presentation.assetSingular,
                    plural: presentation.assetPlural
                ),
                check: .init(
                    singular: presentation.checkSingular,
                    plural: presentation.checkPlural
                ),
                issue: .init(
                    singular: presentation.issueSingular,
                    plural: presentation.issuePlural
                )
            ),
            evidencePurposes: presentation.evidencePurposes.map {
                .init(key: $0.key, display: $0.display, instruction: $0.instruction)
            },
            acknowledgements: presentation.acknowledgements.map {
                .init(key: $0.key, copy: $0.copy, version: $0.version)
            },
            issueLabels: presentation.issueLabels.map {
                .init(key: $0.key, display: $0.display)
            },
            couldNotVerifyReasons: .init(
                version: presentation.couldNotVerifyRegistryVersion,
                entries: presentation.couldNotVerifyReasons.map {
                    .init(key: $0.key, display: $0.display)
                }
            ),
            stageDisplays: presentation.stageDisplays.map {
                .init(key: $0.key, display: $0.display)
            },
            outcomeDisplays: presentation.outcomeDisplays.map {
                .init(key: $0.key, display: $0.display)
            },
            disclaimer: presentation.disclaimer
        )
    }

    private func makeFirstAssetCommand(
        label: String,
        mutationID: MutationIDV1
    ) throws -> WorkspaceCommandV1 {
        let siteID = UUID()
        let placementEventID = UUID()
        return .createFirstSign(FirstSignMutationV1(
            siteID: siteID,
            newSite: .init(
                id: siteID,
                label: "\(label) Site",
                address: nil,
                timeZoneID: "America/New_York"
            ),
            assetID: UUID(),
            assetLabel: label,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            initialPlacementMutationID: mutationID,
            initialPlacementEventID: placementEventID,
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                rawValue: UUID()
            )
        ))
    }

    @MainActor
    private func request(
        mutationID: MutationIDV1,
        command: WorkspaceCommandV1,
        writer: WorkspaceWriterV1
    ) throws -> WorkspaceMutationRequestV1 {
        let current = try writer.currentRevision()
        let identities = try commandTargets(command)
        let known = Dictionary(
            uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) }
        )
        let scoped = try WorkspaceRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            revision: current.revision,
            entityRevisions: identities.map {
                WorkspaceEntityRevisionV1(identity: $0, revision: known[$0, default: 0])
            }
        )
        return WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: scoped),
            command: command
        )
    }

    private func commandTargets(
        _ command: WorkspaceCommandV1
    ) throws -> [WorkspaceEntityIdentityV1] {
        guard case let .createFirstSign(value) = command else {
            throw TestFailure.unsupportedCommand
        }
        var identities = try [
            WorkspaceEntityIdentityV1(kind: .site, id: value.siteID),
            WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
        ]
        if let placementEventID = value.initialPlacementEventID {
            identities.append(try WorkspaceEntityIdentityV1(
                kind: .assetPlacementEvent,
                id: placementEventID
            ))
        }
        return identities
    }

    private func assertPackageOutcomeParity(
        profile: WorkspacePackageLifecycleProfileV1,
        package: SignPack,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let profiles = profile.stages
            .flatMap(\.outcomes)
            .filter { $0.role != .workRecorded }
        XCTAssertEqual(
            Set(profiles.map(\.key)),
            Set(package.outcomeDisplays.map(\.key)),
            file: file,
            line: line
        )
        for outcome in package.outcomeDisplays {
            XCTAssertEqual(
                Set(profiles.filter { $0.key == outcome.key }.map(\.display)),
                Set([outcome.display]),
                file: file,
                line: line
            )
        }
    }
}

@MainActor
private struct Harness {
    let root: URL
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let dependencies: WorkspacePackageLifecycleDependenciesV1

    func cleanup(fileManager: FileManager) {
        withExtendedLifetime(coordinator) {}
        try? fileManager.removeItem(at: root)
    }
}

private enum TestFailure: Error {
    case invalidFixture
    case unsupportedCommand
}
