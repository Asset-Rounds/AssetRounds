import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_11PackRegistryTests: XCTestCase {
    func testV23P03C39BundledSemanticKindUsesExactReleasePolicy() throws {
        let definition = try AssetKindDefinitionV1(
            semanticID: "asset.kind.example",
            displayNameLocalizationKey: "asset.semantic.sign.illuminated.name",
            descriptionLocalizationKey: "asset.semantic.sign.illuminated.description",
            capabilityIDs: [try AssetSemanticCapabilityIDV1("capability.inspect")],
            compatibilityPolicy: .exactReleaseOnly,
            definitionSHA256: String(repeating: "a", count: 64)
        )
        try definition.validate()
        XCTAssertEqual(definition.compatibilityPolicy, .exactReleaseOnly)
        XCTAssertEqual(definition.displayNameLocalizationKey, "asset.semantic.sign.illuminated.name")
    }

    func testV9_11G01ShippingAdapterPreservesIlluminatedSignV1Parity() throws {
        let source = SignPack.illuminatedSignV1
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage(from: source)
        let roundTrip = try ShippingIlluminatedSignAdapterV1.signPack(from: package)
        let parity = try ShippingIlluminatedSignAdapterV1.parityReceipt()

        XCTAssertEqual(roundTrip, source)
        XCTAssertEqual(package.packageID, source.packID)
        XCTAssertEqual(package.contentVersion, source.contentVersion)
        XCTAssertEqual(package.presentation.assetSingular, source.nouns.asset.singular)
        XCTAssertEqual(package.presentation.evidencePurposes.map(\.key), source.evidencePurposes.map(\.key))
        XCTAssertEqual(package.presentation.acknowledgements.map(\.copy), source.acknowledgements.map(\.copy))
        XCTAssertEqual(package.presentation.issueLabels.map(\.key), source.issueLabels.map(\.key))
        XCTAssertEqual(package.presentation.couldNotVerifyReasons.map(\.key), source.couldNotVerifyReasons.entries.map(\.key))
        XCTAssertEqual(package.presentation.stageDisplays.map(\.key), source.stageDisplays.map(\.key))
        XCTAssertEqual(package.presentation.outcomeDisplays.map(\.key), source.outcomeDisplays.map(\.key))
        XCTAssertEqual(package.presentation.disclaimer, source.disclaimer)
        XCTAssertTrue(parity.exactParity)
        XCTAssertEqual(parity.sourceCanonicalSHA256, parity.roundTripCanonicalSHA256)
        XCTAssertTrue(Self.isSHA256(parity.sourceCanonicalSHA256))

        guard case let .available(registry, receipt, bundledParity) =
            BundledInspectionPackageRegistryV2.load() else {
            return XCTFail("The exact shipping package must load from the production bundle")
        }
        XCTAssertEqual(registry.orderedPackages, [package])
        XCTAssertEqual(receipt.orderedPackageIDs, [source.packID])
        XCTAssertEqual(receipt.canonicalPackages, [try InspectionPackageCanonicalCodecV2.encode(package)])
        XCTAssertFalse(receipt.adoptedExistingPublication)
        XCTAssertFalse(receipt.persistentWriteOccurred)
        XCTAssertEqual(bundledParity, parity)
    }

    func testV9_11A01DuplicateUnknownAndIncompatiblePackagesFailClosed() throws {
        let shipping = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let alternate = try fixturePackage()
        let registry = try InspectionPackageRegistryV2(packages: [alternate, shipping])
        XCTAssertEqual(registry.orderedPackageIDs, [shipping.packageID, alternate.packageID].sorted())
        XCTAssertEqual(try registry.package(id: alternate.packageID), alternate)

        assertFailure(.duplicatePackageID) {
            _ = try InspectionPackageRegistryV2(packages: [shipping, shipping])
        }
        assertFailure(.unknownPackage) {
            _ = try registry.package(id: "unknown.package")
        }
        let incompatible = try InspectionPackageV2(
            packageID: "test.field.evidence.incompatible.v1",
            contentVersion: 1,
            minimumRegistryVersion: 3,
            maximumRegistryVersion: 3,
            capabilities: alternate.capabilities,
            permissions: alternate.permissions,
            advisoryGuidance: alternate.advisoryGuidance,
            presentation: alternate.presentation
        )
        assertFailure(.incompatiblePackage) {
            _ = try InspectionPackageRegistryV2(packages: [incompatible])
        }
        let unsupportedContentVersion = try InspectionPackageV2(
            packageID: "test.field.evidence.unsupported-content.v2",
            contentVersion: 2,
            capabilities: alternate.capabilities,
            permissions: alternate.permissions,
            advisoryGuidance: alternate.advisoryGuidance,
            presentation: alternate.presentation
        )
        assertFailure(.incompatiblePackage) {
            _ = try InspectionPackageRegistryPublisherV2.publish(
                packages: [unsupportedContentVersion]
            )
        }

        let missingDeclarations = try InspectionPackageV2(
            packageID: "test.field.evidence.missing-declarations.v1",
            contentVersion: 1,
            capabilities: alternate.capabilities.filter { $0 != .photoCapture },
            permissions: alternate.permissions.filter { $0 != .camera },
            advisoryGuidance: alternate.advisoryGuidance.filter {
                $0.guidanceID != "alternate.safety"
            },
            presentation: alternate.presentation
        )
        assertFailure(.undeclaredCapability) {
            try missingDeclarations.requireCapability(.photoCapture)
        }
        assertFailure(.undeclaredPermission) {
            try missingDeclarations.requirePermission(.camera)
        }
        assertFailure(.undeclaredGuidance) {
            _ = try missingDeclarations.requireGuidance("alternate.safety")
        }

        let fixtureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try fixtureCanonicalData()) as? [String: Any]
        )
        var unknownMember = fixtureObject
        unknownMember["runtimeDownloadURL"] = "https://invalid.example/pack"
        let unknownMemberData = try JSONSerialization.data(
            withJSONObject: unknownMember,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        assertFailure(.nonCanonicalData) {
            _ = try JSONDecoder().decode(InspectionPackageV2.self, from: unknownMemberData)
        }
        assertFailure(.nonCanonicalData) {
            _ = try InspectionPackageCanonicalCodecV2.decode(unknownMemberData)
        }

        let guidance = try XCTUnwrap(
            (fixtureObject["advisoryGuidance"] as? [[String: Any]])?.first
        )
        try assertNestedDecodeRejects(
            InspectionPackageGuidanceV2.self,
            validObject: guidance,
            invalidKey: "guidanceID",
            invalidValue: "INVALID_GUIDANCE"
        )
        let presentation = try XCTUnwrap(fixtureObject["presentation"] as? [String: Any])
        let display = try XCTUnwrap(
            (presentation["issueLabels"] as? [[String: Any]])?.first
        )
        try assertNestedDecodeRejects(
            InspectionPackageDisplayEntryV2.self,
            validObject: display,
            invalidKey: "display",
            invalidValue: ""
        )
        let evidencePurpose = try XCTUnwrap(
            (presentation["evidencePurposes"] as? [[String: Any]])?.first
        )
        try assertNestedDecodeRejects(
            InspectionPackageEvidencePurposeV2.self,
            validObject: evidencePurpose,
            invalidKey: "instruction",
            invalidValue: ""
        )
        let acknowledgement = try XCTUnwrap(
            (presentation["acknowledgements"] as? [[String: Any]])?.first
        )
        try assertNestedDecodeRejects(
            InspectionPackageAcknowledgementV2.self,
            validObject: acknowledgement,
            invalidKey: "version",
            invalidValue: "invalid version"
        )
        try assertNestedDecodeRejects(
            InspectionPackagePresentationV2.self,
            validObject: presentation,
            invalidKey: "assetPlural",
            invalidValue: try XCTUnwrap(presentation["assetSingular"])
        )

        let canonicalText = try XCTUnwrap(String(data: try fixtureCanonicalData(), encoding: .utf8))
        let packageMember = "\"packageID\":\"test.field.evidence.alternate.v1\""
        let duplicateMemberData = try XCTUnwrap(
            canonicalText.replacingOccurrences(
                of: packageMember,
                with: "\(packageMember),\(packageMember)"
            ).data(using: .utf8)
        )
        XCTAssertThrowsError(try InspectionPackageCanonicalCodecV2.decode(duplicateMemberData))

        var unknownEnum = unknownMember
        unknownEnum.removeValue(forKey: "runtimeDownloadURL")
        unknownEnum["capabilities"] = ["RUNTIME_DOWNLOAD"]
        let unknownEnumData = try JSONSerialization.data(
            withJSONObject: unknownEnum,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertThrowsError(try InspectionPackageCanonicalCodecV2.decode(unknownEnumData))
    }

    func testV9_11H01ProductionRegistryAndKernelRemainClosed() throws {
        let shipping = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        XCTAssertEqual(BundledInspectionPackageRegistryV2.source, "BUNDLED_ONLY")
        XCTAssertFalse(BundledInspectionPackageRegistryV2.runtimeDownloadsAllowed)
        XCTAssertEqual(BundledInspectionPackageRegistryV2.shippingPackageIDs, [shipping.packageID])
        XCTAssertEqual(Set(shipping.capabilities), Set(InspectionPackageCapabilityV2.allCases))
        XCTAssertEqual(Set(shipping.permissions), Set(InspectionPackagePermissionV2.allCases))
        XCTAssertEqual(Set(shipping.advisoryGuidance.map(\.kind)), Set(InspectionPackageGuidanceKindV2.allCases))

        XCTAssertTrue(InspectionPackageKernelDependencyBoundaryV2.packageNeutral)
        XCTAssertFalse(InspectionPackageKernelDependencyBoundaryV2.importsFeatureOrUITypes)
        XCTAssertFalse(InspectionPackageKernelDependencyBoundaryV2.signSpecificBranchAllowed)
        XCTAssertEqual(InspectionPackageKernelDependencyBoundaryV2.allowedFoundationDependency, "Foundation")

        let fixtureName = "V21P03C01AlternatePackV1"
        XCTAssertNil(Bundle.main.url(forResource: fixtureName, withExtension: "json"))
        XCTAssertNil(Bundle.main.url(forResource: fixtureName, withExtension: "json", subdirectory: "Fixtures/V21/Packs"))
        XCTAssertNotNil(try fixtureURL())
        XCTAssertThrowsError(try ShippingIlluminatedSignAdapterV1.signPack(from: fixturePackage()))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in [
            "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
            "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
        ] {
            let source = try String(
                contentsOf: root.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains("import Foundation"), relativePath)
            for forbidden in ["import SwiftUI", "SignPack", "Features/", "URLSession", "StoreKit"] {
                XCTAssertFalse(source.contains(forbidden), "\(relativePath) leaked \(forbidden)")
            }
        }
    }

    func testV9_11I01InterruptedRegistryPublicationExposesNoPartialAcceptance() throws {
        let packages = [
            try ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            try fixturePackage(),
        ]
        let complete = try InspectionPackageRegistryPublisherV2.publish(packages: packages)

        for boundary in InspectionPackageRegistryPublicationBoundaryV2.allCases {
            var exposed: InspectionPackageRegistryV2? = nil
            XCTAssertThrowsError(
                try {
                    exposed = try InspectionPackageRegistryPublisherV2.publish(
                        packages: packages
                    ) { reached in
                        if reached == boundary {
                            throw InspectionPackageFailureV2.publicationInterrupted
                        }
                    }.registry
                }()
            ) { error in
                XCTAssertEqual(error as? InspectionPackageFailureV2, .publicationInterrupted)
            }
            XCTAssertNil(exposed)

            let retry = try InspectionPackageRegistryPublisherV2.publish(packages: packages)
            XCTAssertEqual(retry.registry, complete.registry)
            XCTAssertEqual(retry.receipt, complete.receipt)

            var recovered: InspectionPackageRegistryV2? = nil
            XCTAssertThrowsError(
                try {
                    recovered = try InspectionPackageRegistryPublisherV2.recover(
                        canonicalPackages: complete.receipt.canonicalPackages
                    ) { reached in
                        if reached == boundary {
                            throw InspectionPackageFailureV2.publicationInterrupted
                        }
                    }.registry
                }()
            )
            XCTAssertNil(recovered)
            let recoveryRetry = try InspectionPackageRegistryPublisherV2.recover(
                canonicalPackages: complete.receipt.canonicalPackages
            )
            XCTAssertEqual(recoveryRetry.registry, complete.registry)
            XCTAssertTrue(recoveryRetry.receipt.adoptedExistingPublication)
            XCTAssertFalse(recoveryRetry.receipt.persistentWriteOccurred)
        }
    }

    func testV9_11R01DormantRecoveryReturnsSameValidatedShippingPackage() throws {
        let shipping = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let published = try InspectionPackageRegistryPublisherV2.publish(packages: [shipping])
        let recovered = try InspectionPackageRegistryPublisherV2.recover(
            canonicalPackages: published.receipt.canonicalPackages
        )
        let replay = try InspectionPackageRegistryPublisherV2.recover(
            canonicalPackages: recovered.receipt.canonicalPackages
        )

        XCTAssertEqual(recovered.registry, published.registry)
        XCTAssertEqual(replay.registry, recovered.registry)
        XCTAssertEqual(replay.receipt, recovered.receipt)
        XCTAssertEqual(recovered.receipt.orderedPackageIDs, published.receipt.orderedPackageIDs)
        XCTAssertEqual(recovered.receipt.canonicalPackages, published.receipt.canonicalPackages)
        XCTAssertTrue(recovered.receipt.adoptedExistingPublication)
        XCTAssertFalse(recovered.receipt.persistentWriteOccurred)
        XCTAssertEqual(try ShippingIlluminatedSignAdapterV1.signPack(from: recovered.registry.package(id: shipping.packageID)), .illuminatedSignV1)

        XCTAssertEqual(InspectionPackageLifecycleV2.mode, "DECLARATION_ONLY")
        XCTAssertEqual(InspectionPackageLifecycleV2.schema, "PACKAGE_REGISTRY_V2")
        XCTAssertFalse(InspectionPackageLifecycleV2.migrationRequired)
        XCTAssertFalse(InspectionPackageLifecycleV2.backupRestoreRequired)
        XCTAssertFalse(InspectionPackageLifecycleV2.deleteEraseRequired)
        XCTAssertFalse(InspectionPackageLifecycleV2.exportReportRequired)
        XCTAssertEqual(InspectionPackageLifecycleV2.downgradePolicy, "DORMANT_REVERT_ALLOWED")
        XCTAssertFalse(InspectionPackageLifecycleV2.persistent)

        let rawFixture = try Data(contentsOf: fixtureURL())
        XCTAssertEqual(Self.sha256(rawFixture), "4ed3b2cc72778cdd0564cc260d115068db4b207c21d670eb40017a460191cad4")
        let alternate = try fixturePackage()
        XCTAssertEqual(try InspectionPackageCanonicalCodecV2.encode(alternate), try fixtureCanonicalData())
        XCTAssertFalse(BundledInspectionPackageRegistryV2.shippingPackageIDs.contains(alternate.packageID))
    }

    func testV9_11C16ShippingPackageLocalizationSlotsRemainBoundToCatalog() throws {
        let shipping = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let expectedKeys = [
            "package.illuminated_sign.guidance.required_views",
            "package.illuminated_sign.guidance.visible_conditions_only",
            "package.illuminated_sign.guidance.authorized_position",
        ]
        XCTAssertEqual(shipping.advisoryGuidance.map(\.localizationKey), expectedKeys)

        let fixtureData = try Data(contentsOf: try localizationFixtureURL())
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        let catalog = try XCTUnwrap(fixture["catalog"] as? [String: Any])
        let catalogKeys = try XCTUnwrap(catalog["keys"] as? [[String: Any]])
            .compactMap { $0["key"] as? String }
        XCTAssertTrue(Set(expectedKeys).isSubset(of: Set(catalogKeys)))

        let bindings = try XCTUnwrap(fixture["packageBindings"] as? [[String: Any]])
        let binding = try XCTUnwrap(
            bindings.first { ($0["packageID"] as? String) == shipping.packageID }
        )
        XCTAssertEqual(binding["packageContentVersion"] as? Int, shipping.contentVersion)
        XCTAssertEqual(binding["slotKeys"] as? [String], expectedKeys)
        XCTAssertFalse((binding["catalogReleaseID"] as? String ?? "").isEmpty)
        let canonicalKeys = try JSONSerialization.data(
            withJSONObject: catalogKeys.sorted(),
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertEqual(binding["catalogKeyDigest"] as? String, Self.sha256(canonicalKeys))
        XCTAssertEqual(binding["deprecatedKeyFallback"] as? String, "deterministic-source-locale")
    }

    func testV9_11C16PublishedPackageReleaseBindsLocalizationSidecar() throws {
        let workflow = try localizationBindingWorkflow()
        let draft = try BundledInspectionPackageRegistryV2.shippingDraftRelease(
            workflow: workflow
        )
        let tested = try InspectionPackageReleasePublisherV1.test(draft)
        let published = try InspectionPackageReleasePublisherV1.publish(tested)
        let originalPackage = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let sourceCatalog = try Data(contentsOf: repositoryRootURL()
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings"))
        let legacy = try BundledLocalizationCatalogV1.mailLegacyAllowlist()
        let publication = try BundledLocalizationCatalogV1.publish(
            sourceCatalogBytes: sourceCatalog,
            packagePublications: [published],
            legacy: legacy
        )
        guard case let .complete(
            registry: registry,
            accessibility: _,
            legacy: publishedLegacy,
            packageBindings: packageBindings,
            receipt: receipt
        ) = publication else {
            return XCTFail("A published package must produce a complete localization declaration")
        }

        let binding = try XCTUnwrap(packageBindings.first)
        let expectedSlots = try BundledInspectionPackageRegistryV2.shippingLocalizationSlotBindings()
        XCTAssertEqual(binding.packageReleaseID, published.release.packageReleaseID)
        XCTAssertEqual(binding.packageSHA256, published.release.packageSHA256)
        XCTAssertEqual(binding.workflowSHA256, published.release.workflowSHA256)
        XCTAssertEqual(binding.localizationReleaseSHA256, receipt.release.releaseSHA256)
        XCTAssertEqual(binding.sourceCatalogSHA256, receipt.release.sourceCatalogSHA256)
        XCTAssertEqual(binding.keyRegistrySHA256, receipt.release.keyRegistrySHA256)
        XCTAssertEqual(binding.localeManifestSHA256, receipt.release.localeManifestSHA256)
        XCTAssertEqual(binding.orderedSlotBindings, expectedSlots.sorted { $0.slotID < $1.slotID })
        XCTAssertEqual(publishedLegacy, legacy)
        XCTAssertEqual(
            try BundledInspectionPackageRegistryV2.localizationBinding(
                publication: published,
                localizationRelease: receipt.release,
                registry: registry
            ),
            binding
        )
        try binding.validate(
            publication: published,
            localizationRelease: receipt.release,
            registry: registry
        )
        var renamedSlots = expectedSlots
        let first = try XCTUnwrap(renamedSlots.first)
        renamedSlots[0] = PackageLocalizationSlotBindingV1(
            slotID: first.slotID + ".renamed",
            localizationKey: first.localizationKey
        )
        XCTAssertThrowsError(
            try PackageLocalizationReleaseBindingV1(
                publication: published,
                localizationRelease: receipt.release,
                slotBindings: renamedSlots,
                registry: registry
            )
        )

        let publishedPackage = try InspectionPackageCanonicalCodecV2.decode(
            published.release.canonicalPackageBytes
        )
        XCTAssertEqual(publishedPackage, originalPackage)
        XCTAssertEqual(
            try InspectionPackageCanonicalCodecV2.encode(publishedPackage),
            published.release.canonicalPackageBytes
        )
    }

    private func fixturePackage() throws -> InspectionPackageV2 {
        try InspectionPackageCanonicalCodecV2.decode(fixtureCanonicalData())
    }

    private func fixtureCanonicalData() throws -> Data {
        let raw = try Data(contentsOf: fixtureURL())
        guard raw.last == 0x0A else {
            throw V911FixtureFailure.invalidFixture
        }
        let canonical = Data(raw.dropLast())
        guard try InspectionPackageCanonicalCodecV2.encode(
            InspectionPackageCanonicalCodecV2.decode(canonical)
        ) == canonical else {
            throw V911FixtureFailure.invalidFixture
        }
        return canonical
    }

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C01AlternatePackV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Packs"
            ) ?? bundle.url(
                forResource: "V21P03C01AlternatePackV1",
                withExtension: "json"
            )
        )
    }

    private func localizationFixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C16LocalizationAccessibilityCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Localization"
            ) ?? bundle.url(
                forResource: "V21P03C16LocalizationAccessibilityCorpusV1",
                withExtension: "json"
            )
        )
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func localizationBindingWorkflow() throws -> WorkflowDefinitionV1 {
        try WorkflowDefinitionV1(
            workflowID: "fixture.localization.binding.v1",
            entryNodeID: "node.section",
            declaredFieldIDs: [],
            nodes: [
                try WorkflowNodeV1(
                    nodeID: "node.section",
                    kind: .section,
                    localizationKey: "workflow.section",
                    outgoingNodeIDs: ["node.terminal"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.terminal",
                    kind: .terminal,
                    localizationKey: "workflow.terminal",
                    outgoingNodeIDs: []
                ),
            ]
        )
    }

    private func assertFailure(
        _ expected: InspectionPackageFailureV2,
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? InspectionPackageFailureV2, expected, file: file, line: line)
        }
    }

    private func assertNestedDecodeRejects<Value: Decodable>(
        _ type: Value.Type,
        validObject: [String: Any],
        invalidKey: String,
        invalidValue: Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var unknown = validObject
        unknown["unknownMember"] = true
        let unknownData = try JSONSerialization.data(
            withJSONObject: unknown,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        assertFailure(.nonCanonicalData, {
            _ = try JSONDecoder().decode(type, from: unknownData)
        }, file: file, line: line)

        var invalid = validObject
        invalid[invalidKey] = invalidValue
        let invalidData = try JSONSerialization.data(
            withJSONObject: invalid,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        assertFailure(.invalidValue, {
            _ = try JSONDecoder().decode(type, from: invalidData)
        }, file: file, line: line)
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}

private enum V911FixtureFailure: Error {
    case invalidFixture
}

extension V9_11PackRegistryTests {
    func testV23P03C18ActivePointerCarriesReceiptAndReleaseDigests() throws {
        let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c191")!)
        let receiptID = UUID(uuidString: "c1910000-0000-4000-8000-000000000001")!
        let pointer = try ActivePackageRegistryPointerV1(
            pointerID: UUID(uuidString: "c1910000-0000-4000-8000-000000000002")!,
            workspaceID: workspaceID,
            packageID: "com.field-evidence.c18.registry",
            activeReleaseRecordID: UUID(uuidString: "c1910000-0000-4000-8000-000000000003")!,
            promotionReceiptID: receiptID,
            activePackageReleaseID: String(repeating: "c", count: 64),
            activeReleaseRecordSHA256: String(repeating: "d", count: 64),
            revision: 1,
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "c1910000-0000-4000-8000-000000000004")!
            )
        )
        XCTAssertNoThrow(try pointer.validate())
        XCTAssertEqual(pointer.promotionReceiptID, receiptID)
    }
}

extension V9_11PackRegistryTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension V9_11PackRegistryTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(FieldReferenceSubjectKindV1.allCases.count, 2)
        XCTAssertEqual(FieldReferenceSubjectStateV1.allCases.count, 2)
        XCTAssertEqual(FieldReferenceReleaseDispositionV1.allCases.count, 2)
    }
}
extension V9_11PackRegistryTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertTrue(ActivityKindSemanticsV1(kind: .repair).mayClaimRepairPerformed)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .repair).mayClaimInspectionResult)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .repair).mayClaimReleaseToService)
    }
}
extension V9_11PackRegistryTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift_Tests: XCTestCase {
    func testC47V911PackRegistryTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_11PackRegistryTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.disposition(.survey), .exactV1)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.v1(.survey), .survey)
    }
}
