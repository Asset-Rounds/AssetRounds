import CoreImage
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_52AssetLabelTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

@MainActor
final class V9_52AssetLabelTests: XCTestCase {
    func testV23P03C45G01AcceptedPlanGeneratesByteIdenticalPDFCSVTextAndIndependentQRDecode() throws {
        let fixture = try C45AssetLabelTestSupport.fixture(itemCount: 1, disclosure: .assetAndShortCode)
        let first = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let second = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.nativeTextEnvironment, second.nativeTextEnvironment)
        try first.nativeTextEnvironment.validate(planSHA256: fixture.plan.planSHA256)
        XCTAssertGreaterThan(first.nativeTextEnvironment.coreTextVersion, 0)
        XCTAssertTrue(
            first.nativeTextEnvironment.selectedFonts.contains(
                first.nativeTextEnvironment.baseFont
            )
        )
        XCTAssertEqual(first.artifacts.map(\.entry.kind), [.formulaSafeCSV, .pdf, .structuredText])
        XCTAssertEqual(Set(first.artifacts.map(\.entry.itemCount)), [1])
        XCTAssertEqual(first.manifest.planSHA256, fixture.plan.planSHA256)
        XCTAssertEqual(first.manifest.entries.map(\.sha256), second.manifest.entries.map(\.sha256))
        XCTAssertTrue(first.manifest.entries.allSatisfy {
            !$0.safeFilename.localizedCaseInsensitiveContains("Customer") &&
            !$0.safeFilename.localizedCaseInsensitiveContains("Boiler")
        })

        let csv = try XCTUnwrap(first.artifacts.first { $0.entry.kind == .formulaSafeCSV })
        let csvText = try XCTUnwrap(String(data: csv.bytes, encoding: .utf8))
        XCTAssertTrue(csvText.contains("\"'=SUM(1,1)\""))
        XCTAssertFalse(csvText.contains("Customer Site Secret"))

        let accessible = try XCTUnwrap(first.artifacts.first { $0.entry.kind == .structuredText })
        let accessibleText = try XCTUnwrap(String(data: accessible.bytes, encoding: .utf8))
        XCTAssertTrue(accessibleText.contains("claim-boundary\tGenerated locally; not printed, affixed, delivered, or authorization."))
        XCTAssertTrue(accessibleText.contains("short-code\t"))

        let pdf = try XCTUnwrap(first.artifacts.first { $0.entry.kind == .pdf })
        XCTAssertTrue(pdf.bytes.starts(with: Data("%PDF-1.4\n".utf8)))

        let renderedQR = try DeterministicPDFRendererV1.renderAssetLabelQR(fixture.plan.items[0].qrPayload)
        XCTAssertEqual(try renderedQR.decodeCanonicalPayload(), fixture.plan.items[0].qrPayload)
        try DeterministicPDFRendererV1.validateIndependentAssetLabelQRDecode(
            renderedQR,
            decoder: C45IndependentQRDecoder()
        )
        XCTAssertEqual(renderedQR.canonicalPayload, fixture.plan.items[0].qrPayload.canonicalBytes)
        XCTAssertGreaterThan(renderedQR.moduleCountIncludingQuietZone, DeterministicPDFRendererV1.assetLabelQuietZoneModules * 2)
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelInterpolationEnabled)
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelOverlaidLogoEnabled)
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelPhysicalScanAcceptanceClaimed)
        XCTAssertEqual(
            fixture.plan.template.rendererSHA256,
            DeterministicPDFRendererV1.assetLabelRendererSHA256
        )
        XCTAssertEqual(
            fixture.plan.template.rendererRelease,
            try AssetLabelRendererReleaseReferenceV1.current
        )
        XCTAssertEqual(AssetLabelTemplateProfileV1.allCases.count, 5)
        var catalogDigests = Set<String>()
        for profile in AssetLabelTemplateProfileV1.allCases {
            let catalogFixture = try C45AssetLabelTestSupport.fixture(
                itemCount: 1,
                templateProfile: profile
            )
            let release = catalogFixture.plan.template
            XCTAssertEqual(release.templateID, profile.rawValue)
            XCTAssertEqual(release.pageMediaID, AssetLabelTemplateCatalogV1.pageMediaID(for: profile))
            XCTAssertEqual(release.geometry, try AssetLabelTemplateCatalogV1.geometry(for: profile))
            XCTAssertEqual(
                release.rendererRelease,
                try AssetLabelRendererReleaseReferenceV1.current
            )
            XCTAssertEqual(
                try DeterministicPDFRendererV1.renderAssetLabels(catalogFixture.plan).artifacts.count,
                LabelArtifactKindV1.allCases.count
            )
            catalogDigests.insert(release.templateSHA256)
        }
        XCTAssertEqual(catalogDigests.count, AssetLabelTemplateProfileV1.allCases.count)

        let assetCanary = "C45_ASSET_CUSTOMER_CANARY"
        let locationCanary = "C45_LOCATION_CUSTOMER_CANARY"
        let assetOnly = try C45AssetLabelTestSupport.fixture(
            itemCount: 1,
            disclosure: .assetAndShortCode,
            assetDisplay: assetCanary
        )
        let assetOnlyProjection = try DeterministicPDFRendererV1.renderAssetLabels(assetOnly.plan)
        for artifact in assetOnlyProjection.artifacts where artifact.entry.kind != .pdf {
            XCTAssertTrue(artifact.bytes.range(of: Data(assetCanary.utf8)) != nil, artifact.entry.safeFilename)
            XCTAssertNil(artifact.bytes.range(of: Data(locationCanary.utf8)), artifact.entry.safeFilename)
        }
        let assetOnlyPDF = try XCTUnwrap(
            assetOnlyProjection.artifacts.first { $0.entry.kind == .pdf }
        )
        let assetOnlyInspection = try DeterministicPDFRendererV1.inspectAssetLabelPDFText(
            assetOnlyPDF.bytes
        )
        XCTAssertEqual(assetOnlyInspection.isolatedLinesByItem.count, 1)
        XCTAssertTrue(assetOnlyInspection.isolatedLinesByItem[0].contains {
            $0.contains(assetCanary)
        })
        XCTAssertFalse(assetOnlyInspection.isolatedLinesByItem[0].contains {
            $0.contains(locationCanary)
        })
        XCTAssertFalse(assetOnlyInspection.usesType1TextOperators)
        let assetAndLocation = try C45AssetLabelTestSupport.fixture(
            itemCount: 1,
            disclosure: .assetLocationAndShortCode,
            assetDisplay: assetCanary,
            locationDisplay: locationCanary
        )
        let expandedProjection = try DeterministicPDFRendererV1.renderAssetLabels(assetAndLocation.plan)
        for artifact in expandedProjection.artifacts where artifact.entry.kind != .pdf {
            XCTAssertTrue(artifact.bytes.range(of: Data(assetCanary.utf8)) != nil, artifact.entry.safeFilename)
            XCTAssertTrue(artifact.bytes.range(of: Data(locationCanary.utf8)) != nil, artifact.entry.safeFilename)
        }
        let expandedPDF = try XCTUnwrap(
            expandedProjection.artifacts.first { $0.entry.kind == .pdf }
        )
        let expandedInspection = try DeterministicPDFRendererV1.inspectAssetLabelPDFText(
            expandedPDF.bytes
        )
        XCTAssertEqual(expandedInspection.isolatedLinesByItem.count, 1)
        XCTAssertTrue(expandedInspection.isolatedLinesByItem[0].contains {
            $0.contains(assetCanary)
        })
        XCTAssertTrue(expandedInspection.isolatedLinesByItem[0].contains {
            $0.contains(locationCanary)
        })
        XCTAssertFalse(expandedInspection.usesType1TextOperators)

        let rtlAsset = String(repeating: "משאבה صناعية ארוכה ", count: 7)
            .precomposedStringWithCanonicalMapping
        let rtlLocation = (
            String(repeating: "gypqj ", count: 4)
                + String(repeating: "חדר שירות موقع شرقي ", count: 5)
        )
            .precomposedStringWithCanonicalMapping
        let rtlFixture = try C45AssetLabelTestSupport.fixture(
            itemCount: 1,
            disclosure: .assetLocationAndShortCode,
            assetDisplay: rtlAsset,
            locationDisplay: rtlLocation,
            templateProfile: .a4SeventyByThirtySeven
        )
        let rtlText = try DeterministicPDFRendererV1.renderAssetLabelText(
            rtlFixture.plan.items[0],
            pixelWidth: 158,
            pixelHeight: 30
        )
        XCTAssertEqual(
            rtlText,
            try DeterministicPDFRendererV1.renderAssetLabelText(
                rtlFixture.plan.items[0],
                pixelWidth: 158,
                pixelHeight: 30
            )
        )
        XCTAssertEqual(rtlText.isolatedLines.count, 3)
        XCTAssertEqual(rtlText.grayscaleBytes.count, rtlText.pixelWidth * rtlText.pixelHeight)
        XCTAssertEqual(
            rtlText.fontPostScriptName,
            DeterministicPDFRendererV1.assetLabelNativeFontPostScriptName
        )
        XCTAssertTrue(rtlText.isolatedLines.allSatisfy {
            $0.hasPrefix(DeterministicPDFRendererV1.assetLabelBidiIsolationPrefix)
                && $0.hasSuffix(DeterministicPDFRendererV1.assetLabelBidiIsolationSuffix)
        })
        XCTAssertTrue(rtlText.isolatedLines[1].dropLast().hasSuffix("..."))
        XCTAssertTrue(rtlText.isolatedLines[2].dropLast().hasSuffix("..."))
        XCTAssertTrue(rtlText.isolatedLines.allSatisfy { $0.count <= 32 })
        let rasterRows = (0..<rtlText.pixelHeight).map { row in
            rtlText.grayscaleBytes[
                (row * rtlText.pixelWidth)..<((row + 1) * rtlText.pixelWidth)
            ]
        }
        XCTAssertTrue(rasterRows[0].allSatisfy { $0 == 255 })
        XCTAssertTrue(rasterRows[rtlText.pixelHeight - 1].allSatisfy { $0 == 255 })
        for lineBox in 0..<3 {
            let box = rasterRows[(lineBox * 10)..<((lineBox + 1) * 10)]
            XCTAssertTrue(box.contains { row in row.contains { $0 < 255 } })
        }

        let rtlProjection = try DeterministicPDFRendererV1.renderAssetLabels(rtlFixture.plan)
        XCTAssertEqual(
            rtlProjection,
            try DeterministicPDFRendererV1.renderAssetLabels(rtlFixture.plan)
        )
        let rtlPDF = try XCTUnwrap(
            rtlProjection.artifacts.first { $0.entry.kind == .pdf }
        )
        let textInspection = try DeterministicPDFRendererV1.inspectAssetLabelPDFText(
            rtlPDF.bytes
        )
        XCTAssertEqual(textInspection.isolatedLinesByItem, [rtlText.isolatedLines])
        XCTAssertFalse(textInspection.usesType1TextOperators)
        let pdfProvider = try XCTUnwrap(CGDataProvider(data: rtlPDF.bytes as CFData))
        let parsedPDF = try XCTUnwrap(CGPDFDocument(pdfProvider))
        XCTAssertEqual(parsedPDF.numberOfPages, 1)
        XCTAssertThrowsError(try DeterministicPDFRendererV1.renderAssetLabelText(
            rtlFixture.plan.items[0],
            pixelWidth: 158,
            pixelHeight: 29
        )) {
            XCTAssertEqual($0 as? AssetLabelRenderFailureV1, .contentDoesNotFit)
        }

        let output = try C45AssetLabelTestSupport.output(
            plan: fixture.plan,
            result: first,
            slot: 600
        )
        let snapshot = try C45AssetLabelTestSupport.snapshot(
            fixture: fixture,
            result: first,
            output: output,
            slot: 610
        )
        let mutation = try AssetLabelMutationV1(snapshot: snapshot)
        let request = try AssetLabelAcceptanceRequestV1(mutation: mutation)
        XCTAssertEqual(request.snapshot.snapshotSHA256, snapshot.snapshotSHA256)
        XCTAssertEqual(request.mutation.mutationSHA256, mutation.mutationSHA256)
        XCTAssertEqual(snapshot.activationDecision, .enabledBoundedLocalOnly)
        XCTAssertEqual(snapshot.outputReceipt.disposition, .generated)
        XCTAssertEqual(snapshot.disposition, .activeSourceWorkspace)

        let row = try AcceptedLabelGenerationSnapshotRow(snapshot)
        XCTAssertEqual(try row.value(), snapshot)
        XCTAssertEqual(row.canonicalData, try AssetLabelCanonicalCodecV1.encode(snapshot))
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentSchemaVersion, 34)
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion, 33)
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentFamilies, ["AcceptedLabelGenerationSnapshotRow"])
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.durableModelCount, 1)
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.createsSecondLocatorStore)
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.createsSecondRenderer)
    }

    func testV23P03C45A01ManualShortCodeAndCameraResolutionParityPreserveExplicitStart() async throws {
        let fixture = try C45AssetLabelTestSupport.fixture(itemCount: 30, disclosure: .shortCodeOnly, startOffset: 7)
        XCTAssertEqual(fixture.plan.startOffset, 7)
        XCTAssertEqual(fixture.plan.startDecision, .explicitStartRequired)
        XCTAssertEqual(fixture.plan.orderingPolicy, .explicitSelectionOrderThenAssetID)
        XCTAssertEqual(fixture.plan.items.count, 30)
        XCTAssertEqual(fixture.plan.items.map(\.orderIndex), Array(0..<30))
        XCTAssertEqual(Set(fixture.plan.items.map(\.assetID)).count, 30)
        let reorderedInput = try AssetLabelGenerationPlanV1(
            planID: fixture.plan.planID,
            workspaceID: fixture.plan.workspaceID,
            template: fixture.plan.template,
            disclosure: fixture.plan.disclosure,
            items: Array(fixture.plan.items.reversed()),
            startOffset: fixture.plan.startOffset,
            localeIdentifier: fixture.plan.localeIdentifier,
            frozenGeneratedAt: fixture.plan.frozenGeneratedAt
        )
        XCTAssertEqual(reorderedInput.items, fixture.plan.items)
        XCTAssertEqual(reorderedInput.planSHA256, fixture.plan.planSHA256)
        let tiedFirst = try C45AssetLabelTestSupport.item(
            index: 31,
            workspaceID: fixture.plan.workspaceID,
            templateDisclosure: fixture.plan.disclosure,
            orderIndex: 0
        ).item
        let tiedSecond = try C45AssetLabelTestSupport.item(
            index: 30,
            workspaceID: fixture.plan.workspaceID,
            templateDisclosure: fixture.plan.disclosure,
            orderIndex: 0
        ).item
        let tiedPlan = try AssetLabelGenerationPlanV1(
            planID: C45AssetLabelTestSupport.id(32),
            workspaceID: fixture.plan.workspaceID,
            template: fixture.plan.template,
            disclosure: fixture.plan.disclosure,
            items: [tiedFirst, tiedSecond],
            startOffset: fixture.plan.startOffset,
            localeIdentifier: fixture.plan.localeIdentifier
        )
        XCTAssertEqual(tiedPlan.items.map(\.assetID), [tiedSecond.assetID, tiedFirst.assetID])
        XCTAssertEqual(tiedPlan.items.map(\.orderIndex), [0, 1])

        let item = fixture.plan.items[0]
        let bytes = Data(item.shortCode.canonicalLocatorValue.utf8)
        let decoder = AssetLocatorInputDecoderV1()
        let query = C45LocatorQuery(locator: fixture.locators[0])
        let coordinator = AssetLocatorCoordinatorV1(
            resolver: OfflineAssetLocatorResolverV1(
                query: query,
                signatureVerifier: C45RejectingSignatureVerifier()
            )
        )
        let cameraInput = try decoder.externalKey(
            bytes,
            namespaceID: ManualShortCodeV1.externalKeyNamespace,
            normalization: .asciiCaseInsensitive,
            source: .camera
        )
        let manualInput = try decoder.externalKey(
            bytes,
            namespaceID: ManualShortCodeV1.externalKeyNamespace,
            normalization: .asciiCaseInsensitive,
            source: .manual
        )
        let camera = try await coordinator.resolveCamera(
            cameraInput,
            workspaceID: fixture.plan.workspaceID,
            evaluatedAt: C45AssetLabelTestSupport.date(700)
        )
        let manual = try await coordinator.resolveManual(
            manualInput,
            workspaceID: fixture.plan.workspaceID,
            evaluatedAt: C45AssetLabelTestSupport.date(700)
        )
        XCTAssertEqual(camera.outcome, .matched)
        XCTAssertEqual(manual.outcome, .matched)
        XCTAssertEqual(camera.matchedAssetID, manual.matchedAssetID)
        XCTAssertEqual(camera.matchedLocator, manual.matchedLocator)
        XCTAssertEqual(camera.inputSHA256, manual.inputSHA256)
        XCTAssertEqual(camera.source, .camera)
        XCTAssertEqual(manual.source, .manual)

        let bodies = ["23456789AB", "CDEFGHJKMN", "ZZZZZZZZZZ", "2222222222"]
        for body in bodies {
            let code = try ManualShortCodeV1(randomBody: body)
            XCTAssertEqual(try ManualShortCodeV1(displayValue: code.displayValue), code)
            XCTAssertEqual(try AssetLabelOpaqueQRPayloadV1(canonicalBytes: Data(code.canonicalLocatorValue.utf8)).shortCode, code)
            XCTAssertTrue(code.randomBody.allSatisfy { ManualShortCodeV1.alphabet.contains($0) })
        }
        XCTAssertEqual(ManualShortCodeV1.randomBodyLength, 10)
        XCTAssertEqual(ManualShortCodeV1.alphabet, "23456789ABCDEFGHJKMNPQRSTUVWXYZ")
        XCTAssertEqual(AssetLabelOpaqueQRPayloadV1.prefix, "AR1")
        XCTAssertLessThanOrEqual(item.qrPayload.canonicalBytes.count, AssetLabelOpaqueQRPayloadV1.maximumPayloadBytes)

        for count in [1, 30, 500, AssetLabelGenerationPlanV1.maximumItemCount] {
            let plan = try C45AssetLabelTestSupport.fixture(itemCount: count).plan
            XCTAssertEqual(plan.items.count, count)
            XCTAssertEqual(plan.items.last?.orderIndex, count - 1)
            XCTAssertEqual(Set(plan.items.map(\.assetID)).count, count)
        }
    }

    func testV23P03C45H01MalformedStaleRevokedAndOversizedInputsFailClosedWithoutWrongEntity() throws {
        let fixture = try C45AssetLabelTestSupport.fixture(itemCount: 2, disclosure: .assetLocationAndShortCode)
        let valid = fixture.plan.items[0]
        let malformed: [Data] = [
            Data(), Data("AR1:23456".utf8), Data("ZZ1:23456789AB:A".utf8),
            Data("AR1:23456789AB:2".utf8), Data(repeating: 0x41, count: AssetLabelOpaqueQRPayloadV1.maximumPayloadBytes + 1),
        ]
        for bytes in malformed {
            XCTAssertThrowsError(try AssetLabelOpaqueQRPayloadV1(canonicalBytes: bytes))
        }
        XCTAssertThrowsError(try ManualShortCodeV1(randomBody: "0000000000"))
        XCTAssertThrowsError(try ManualShortCodeV1(randomBody: "IIIIIIIIII"))
        XCTAssertThrowsError(try ManualShortCodeV1(displayValue: valid.shortCode.displayValue + "-EXTRA"))

        XCTAssertThrowsError(try AssetLabelGeometryV1(
            pageWidthMicrometres: 10_000,
            pageHeightMicrometres: 10_000,
            rows: 1,
            columns: 1,
            originXMicrometres: 0,
            originYMicrometres: 0,
            cellWidthMicrometres: 20_000,
            cellHeightMicrometres: 20_000,
            horizontalGapMicrometres: 0,
            verticalGapMicrometres: 0,
            quietZoneMicrometres: 1_000,
            textBoundMicrometres: 2_000
        ))

        XCTAssertThrowsError(try AssetLabelGenerationPlanV1(
            planID: C45AssetLabelTestSupport.id(800),
            workspaceID: fixture.plan.workspaceID,
            template: fixture.plan.template,
            disclosure: fixture.plan.disclosure,
            items: [valid, valid],
            startOffset: 0,
            localeIdentifier: "en_US_POSIX"
        ))

        let bidi = "Asset\u{202E}evil"
        XCTAssertThrowsError(try C45AssetLabelTestSupport.item(
            index: 0,
            workspaceID: fixture.plan.workspaceID,
            templateDisclosure: .assetAndShortCode,
            assetDisplay: bidi
        ))

        let revoked = try C45AssetLabelTestSupport.currentBinding(item: valid, state: .revoked)
        let staleAsset = try C45AssetLabelTestSupport.currentBinding(item: valid, assetRevision: valid.assetRevision + 1)
        let staleLocator = try C45AssetLabelTestSupport.currentBinding(item: valid, bindingRevision: valid.bindingReceiptRevision + 1)
        let one = try C45AssetLabelTestSupport.fixture(itemCount: 1)
        let projected = try DeterministicPDFRendererV1.renderAssetLabels(one.plan)
        let output = try C45AssetLabelTestSupport.output(plan: one.plan, result: projected, slot: 810)
        let snapshot = try C45AssetLabelTestSupport.snapshot(fixture: one, result: projected, output: output, slot: 820)
        let contexts = try [revoked, staleAsset, staleLocator].map {
            try AssetLabelReprintContextV1(
                templateRelease: try fixture.plan.template.reference,
                rendererRelease: fixture.plan.template.rendererRelease,
                nativeTextEnvironment: snapshot.outputReceipt.nativeTextEnvironment,
                currentBindings: [$0]
            )
        }
        for context in contexts {
            XCTAssertEqual(try snapshot.reprintEligibility(in: context), .historicExportOnly)
        }
        XCTAssertEqual(
            try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
                templateRelease: nil,
                rendererRelease: snapshot.plan.template.rendererRelease,
                nativeTextEnvironment: snapshot.outputReceipt.nativeTextEnvironment,
                currentBindings: [try C45AssetLabelTestSupport.currentBinding(item: one.plan.items[0])]
            )),
            .blockedMissingRelease
        )
        XCTAssertThrowsError(try AssetLabelRendererReleaseReferenceV1(
            rendererID: snapshot.plan.template.rendererRelease.rendererID,
            rendererVersion: snapshot.plan.template.rendererRelease.rendererVersion,
            rendererSHA256: snapshot.plan.template.rendererRelease.rendererSHA256,
            nativeTextLayoutReleaseID: snapshot.plan.template.rendererRelease.nativeTextLayoutReleaseID
                + "-UNBOUND-RUNTIME"
        )) {
            XCTAssertEqual($0 as? AssetLabelContractFailureV1, .missingRelease)
        }
        let exactReleaseContext = try AssetLabelReprintContextV1(
            templateRelease: snapshot.plan.template.reference,
            rendererRelease: snapshot.plan.template.rendererRelease,
            nativeTextEnvironment: snapshot.outputReceipt.nativeTextEnvironment,
            currentBindings: [try C45AssetLabelTestSupport.currentBinding(item: one.plan.items[0])]
        )
        XCTAssertEqual(
            try DeterministicPDFRendererV1.assetLabelNativeTextEnvironment(for: snapshot.plan),
            snapshot.outputReceipt.nativeTextEnvironment
        )
        XCTAssertEqual(try snapshot.reprintEligibility(in: exactReleaseContext), .activeExactReprint)
        XCTAssertEqual(try snapshot.reprintEligibility(in: exactReleaseContext), .activeExactReprint)
        let acceptedTextEnvironment = snapshot.outputReceipt.nativeTextEnvironment
        let extraFontEnvironment = try AssetLabelNativeTextEnvironmentV1(
            planSHA256: acceptedTextEnvironment.planSHA256,
            nativeTextLayoutReleaseID: acceptedTextEnvironment.nativeTextLayoutReleaseID,
            coreTextVersion: acceptedTextEnvironment.coreTextVersion,
            operatingSystemBuild: acceptedTextEnvironment.operatingSystemBuild,
            baseFont: acceptedTextEnvironment.baseFont,
            selectedFonts: acceptedTextEnvironment.selectedFonts + [
                try AssetLabelNativeFontIdentityV1(
                    postScriptName: "TimesNewRomanPSMT",
                    fontFileSHA256: C45AssetLabelTestSupport.digest("c")
                )
            ]
        )
        let mutatedCoreTextEnvironment = try AssetLabelNativeTextEnvironmentV1(
            planSHA256: acceptedTextEnvironment.planSHA256,
            nativeTextLayoutReleaseID: acceptedTextEnvironment.nativeTextLayoutReleaseID,
            coreTextVersion: acceptedTextEnvironment.coreTextVersion == .max
                ? acceptedTextEnvironment.coreTextVersion - 1
                : acceptedTextEnvironment.coreTextVersion + 1,
            operatingSystemBuild: acceptedTextEnvironment.operatingSystemBuild,
            baseFont: acceptedTextEnvironment.baseFont,
            selectedFonts: acceptedTextEnvironment.selectedFonts
        )
        let mutatedOperatingSystemEnvironment = try AssetLabelNativeTextEnvironmentV1(
            planSHA256: acceptedTextEnvironment.planSHA256,
            nativeTextLayoutReleaseID: acceptedTextEnvironment.nativeTextLayoutReleaseID,
            coreTextVersion: acceptedTextEnvironment.coreTextVersion,
            operatingSystemBuild: acceptedTextEnvironment.operatingSystemBuild + "-MISMATCH",
            baseFont: acceptedTextEnvironment.baseFont,
            selectedFonts: acceptedTextEnvironment.selectedFonts
        )
        let mutatedBaseFont = try AssetLabelNativeFontIdentityV1(
            postScriptName: acceptedTextEnvironment.baseFont.postScriptName,
            fontFileSHA256: C45AssetLabelTestSupport.digest("d")
        )
        let mutatedFontDigestEnvironment = try AssetLabelNativeTextEnvironmentV1(
            planSHA256: acceptedTextEnvironment.planSHA256,
            nativeTextLayoutReleaseID: acceptedTextEnvironment.nativeTextLayoutReleaseID,
            coreTextVersion: acceptedTextEnvironment.coreTextVersion,
            operatingSystemBuild: acceptedTextEnvironment.operatingSystemBuild,
            baseFont: mutatedBaseFont,
            selectedFonts: acceptedTextEnvironment.selectedFonts.map {
                $0 == acceptedTextEnvironment.baseFont ? mutatedBaseFont : $0
            }
        )
        for mismatchedEnvironment in [
            extraFontEnvironment,
            mutatedCoreTextEnvironment,
            mutatedOperatingSystemEnvironment,
            mutatedFontDigestEnvironment,
        ] {
            XCTAssertNotEqual(mismatchedEnvironment, acceptedTextEnvironment)
            XCTAssertEqual(
                try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
                    templateRelease: snapshot.plan.template.reference,
                    rendererRelease: snapshot.plan.template.rendererRelease,
                    nativeTextEnvironment: mismatchedEnvironment,
                    currentBindings: exactReleaseContext.currentBindings
                )),
                .blockedMissingRelease
            )
        }
        XCTAssertEqual(
            try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
                templateRelease: snapshot.plan.template.reference,
                rendererRelease: nil,
                nativeTextEnvironment: snapshot.outputReceipt.nativeTextEnvironment,
                currentBindings: exactReleaseContext.currentBindings
            )),
            .blockedMissingRelease
        )
        XCTAssertNotEqual(valid.assetID, fixture.plan.items[1].assetID)
        XCTAssertNotEqual(valid.locator.locatorID, fixture.plan.items[1].locator.locatorID)
        try C45AssetLabelTestSupport.verifyPublicationBindingAndOwnershipHostiles(slot: 830)
    }

    func testV23P03C45I01LocatorIssuanceAndRenderPublicationRecoverZeroOrCompleteWithoutPartialOutput() async throws {
        let interruptionBoundaries = [
            "before locator issuance receipt",
            "after locator issuance receipt",
            "each render checkpoint interruption",
            "after final bytes before publication",
        ]
        XCTAssertEqual(interruptionBoundaries.count, 4)
        XCTAssertEqual(
            AssetLabelRenderCheckpointV1.allCases,
            [.validatedPlan, .renderedPDF, .renderedFormulaSafeCSV, .renderedStructuredText, .sealedManifest]
        )
        XCTAssertEqual(AssetLabelRenderCheckpointV1.totalUnitCount, 5)
        let fixture = try C45AssetLabelTestSupport.fixture(itemCount: 1)
        let authority = C45PlanAuthority()
        let renderer = C45ProjectionRenderer()
        let writer = C45FailClosedWriter()
        let query = C45AcceptedSnapshotQuery()
        let coordinator = AssetLabelCoordinatorV1(
            authority: authority,
            renderer: renderer,
            writer: writer,
            query: query
        )

        renderer.failNext = true
        await XCTAssertThrowsErrorAsync {
            _ = try await coordinator.projectValidatedPlan(fixture.plan)
        }
        XCTAssertEqual(renderer.completed.count, 0)
        XCTAssertEqual(writer.commitCount, 0)

        let projection = try await coordinator.projectValidatedPlan(fixture.plan)
        XCTAssertEqual(renderer.completed, [fixture.plan.planSHA256])
        let scratchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("c45-label-scratch-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratchRoot) }
        let scratch = try AssetLabelArtifactOperationsV1.durableStaging(
            jobStagingRootURL: scratchRoot,
            publishOrAdopt: { _, _, _ in throw AssetLabelLifecycleFailureV1.publicationMismatch },
            adoptOnly: { _, _, _ in throw AssetLabelLifecycleFailureV1.publicationMismatch },
            publishedReadback: { _, _, _ in nil },
            removePublishedOutput: { _ in },
            removePublishedWorkspace: { _ in },
            eraseAllPublished: {},
            discardUncommitted: { _ in }
        )
        let jobID = LocalJobIDV1.deterministic(
            kind: .render,
            workspaceID: fixture.plan.workspaceID.rawValue,
            immutableInputSHA256: fixture.plan.planSHA256
        )
        try await scratch.stage(jobID, fixture.plan, projection)
        let staged = try await scratch.load(jobID, fixture.plan.planSHA256)
        XCTAssertEqual(staged?.0, fixture.plan)
        XCTAssertEqual(staged?.1, projection)
        let output = try C45AssetLabelTestSupport.output(plan: fixture.plan, result: projection, slot: 900)
        let request = try await coordinator.makeAcceptanceRequest(
            snapshotID: C45AssetLabelTestSupport.id(901),
            plan: fixture.plan,
            projection: projection,
            outputReceipt: output,
            activationDecision: .enabledBoundedLocalOnly,
            expectedRevision: try C45AssetLabelTestSupport.expectedRevision(
                workspaceID: fixture.plan.workspaceID,
                snapshotID: C45AssetLabelTestSupport.id(901),
                slot: 902
            ),
            mutationID: C45AssetLabelTestSupport.mutation(903),
            recordedBy: try C45AssetLabelTestSupport.actor(workspaceID: fixture.plan.workspaceID, slot: 904),
            recordedAt: C45AssetLabelTestSupport.date(905)
        )
        writer.failNext = true
        await XCTAssertThrowsErrorAsync { _ = try await coordinator.accept(request) }
        XCTAssertEqual(writer.commitCount, 1)

        let row = try AcceptedLabelGenerationSnapshotRow(request.snapshot)
        writer.recoveredSnapshot = try row.value()
        query.snapshots[request.snapshot.snapshotID] = request.snapshot
        query.byMutation[request.mutationID] = request.snapshot
        let recoveredByMutation = try await coordinator.acceptedSnapshot(
            workspaceID: request.workspaceID,
            mutationID: request.mutationID
        )
        let recoveredBySnapshot = try await coordinator.acceptedSnapshot(
            workspaceID: request.workspaceID,
            snapshotID: request.snapshot.snapshotID
        )
        XCTAssertEqual(
            recoveredByMutation,
            request.snapshot
        )
        XCTAssertEqual(
            recoveredBySnapshot,
            request.snapshot
        )
        XCTAssertEqual(try row.value().snapshotSHA256, request.snapshot.snapshotSHA256)
        XCTAssertEqual(try AssetLabelCanonicalCodecV1.decode(AcceptedLabelGenerationSnapshotV1.self, from: row.canonicalData), request.snapshot)
        try await scratch.discard(jobID)
        let discardedScratch = try await scratch.load(jobID, fixture.plan.planSHA256)
        XCTAssertNil(discardedScratch)
        try await C45AssetLabelTestSupport.verifyRealShortCodeIssuanceRecovery(slot: 925)
        try await C45AssetLabelTestSupport.verifyEvidenceBundlePublicationRecovery(slot: 940)
        try await C45AssetLabelTestSupport.verifyResumableRunnerRelaunch(slot: 950)
    }

    func testV23P03C45R01BackupRestoreReplayDeleteEraseReprintAndScratchCleanupRemainExact() async throws {
        let source = try C45AssetLabelTestSupport.fixture(itemCount: 1)
        let result = try DeterministicPDFRendererV1.renderAssetLabels(source.plan)
        let output = try C45AssetLabelTestSupport.output(plan: source.plan, result: result, slot: 1_000)
        let snapshot = try C45AssetLabelTestSupport.snapshot(fixture: source, result: result, output: output, slot: 1_010)
        let canonical = try AssetLabelCanonicalCodecV1.encode(snapshot)
        let row = try AcceptedLabelGenerationSnapshotRow(snapshot)
        XCTAssertEqual(row.canonicalData, canonical)
        XCTAssertEqual(try row.value(), snapshot)
        let backupRecord = try V34BackupAcceptedLabelSnapshotRecordV1(snapshot)
        XCTAssertEqual(try backupRecord.value(), snapshot)
        XCTAssertEqual(backupRecord.canonicalData, canonical)
        let canonicalReceipt = try C45AssetLabelTestSupport.canonicalReceipt(snapshot: snapshot)
        let historyRecord = MutationHistoryReceiptRecordV1(
            envelopeData: try MutationEnvelopeV1(
                request: AssetLabelMutationV1(snapshot: snapshot).canonicalWorkspaceMutationRequest(),
                identity: WorkspaceReplicaIdentityV1(
                    workspaceID: snapshot.workspaceID,
                    replicaID: canonicalReceipt.identity.replicaID
                )
            ).canonicalData(),
            receiptData: try canonicalReceipt.canonicalData(),
            reversalBasisData: nil,
            semanticReversalData: nil
        )
        let backupRecords = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [],
            mutationHistory: MutationHistorySnapshotV1(
                workspaceRevision: 1,
                lastLocalSequence: 1,
                receipts: [historyRecord],
                quarantines: [],
                entityRevisions: [
                    MutationHistoryEntityRevisionV1(
                        identity: try AssetLabelMutationV1(snapshot: snapshot).affectedIdentity,
                        revision: snapshot.revision,
                        externalProjectionSHA256: snapshot.snapshotSHA256
                    )
                ]
            ),
            packets: [],
            recordsSchemaVersion: AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [],
            acceptedLabelGenerationSnapshots: [backupRecord]
        )
        XCTAssertEqual(try backupRecords.validateC45AcceptedLabelSnapshots(), [snapshot])
        try C45AcceptedLabelBackupImportPolicyV1.validate(backupRecords)

        let schema = Schema(PersistentSchemaV34.models, version: PersistentSchemaV34.versionIdentifier)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C45AcceptedSnapshot-R01",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        context.insert(row)
        try context.save()
        let durableQuery = AcceptedLabelGenerationSnapshotQueryV1(modelContext: context)
        let persistedByMutation = try await durableQuery.acceptedLabelSnapshot(
            workspaceID: snapshot.workspaceID,
            mutationID: snapshot.mutationID
        )
        let persistedBySnapshot = try await durableQuery.acceptedLabelSnapshot(
            workspaceID: snapshot.workspaceID,
            snapshotID: snapshot.snapshotID
        )
        XCTAssertEqual(
            persistedByMutation,
            snapshot
        )
        XCTAssertEqual(
            persistedBySnapshot,
            snapshot
        )

        let destinationWorkspace = C45AssetLabelTestSupport.workspace(1_020)
        let historic = try snapshot.rebound(
            to: destinationWorkspace,
            expectedRevision: try C45AssetLabelTestSupport.expectedRevision(
                workspaceID: destinationWorkspace,
                snapshotID: snapshot.snapshotID,
                slot: 1_021
            ),
            mutationID: C45AssetLabelTestSupport.mutation(1_022),
            recordedBy: try C45AssetLabelTestSupport.actor(workspaceID: destinationWorkspace, slot: 1_023),
            recordedAt: C45AssetLabelTestSupport.date(1_024)
        )
        XCTAssertEqual(historic.disposition, .historicCloneOrFork)
        XCTAssertEqual(historic.plan, snapshot.plan)
        XCTAssertEqual(historic.manifest, snapshot.manifest)
        XCTAssertEqual(historic.outputReceipt, snapshot.outputReceipt)
        XCTAssertEqual(historic.plan.workspaceID, snapshot.plan.workspaceID)
        XCTAssertEqual(historic.plan.items.map(\.shortCode), snapshot.plan.items.map(\.shortCode))
        XCTAssertEqual(historic.plan.items.map(\.locator), snapshot.plan.items.map(\.locator))
        XCTAssertEqual(historic.manifest.entries, snapshot.manifest.entries)
        XCTAssertNotEqual(historic.workspaceID, snapshot.workspaceID)
        XCTAssertNotEqual(historic.snapshotSHA256, snapshot.snapshotSHA256)
        XCTAssertEqual(
            try historic.reprintEligibility(in: AssetLabelReprintContextV1(
                templateRelease: try historic.plan.template.reference,
                rendererRelease: historic.plan.template.rendererRelease,
                nativeTextEnvironment: historic.outputReceipt.nativeTextEnvironment,
                currentBindings: []
            )),
            .historicExportOnly
        )
        XCTAssertEqual(
            try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
                templateRelease: nil,
                rendererRelease: nil,
                nativeTextEnvironment: nil,
                currentBindings: []
            )),
            .blockedMissingRelease
        )

        let active = try C45AssetLabelTestSupport.currentBinding(item: snapshot.plan.items[0])
        XCTAssertEqual(
            try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
                templateRelease: try snapshot.plan.template.reference,
                rendererRelease: snapshot.plan.template.rendererRelease,
                nativeTextEnvironment: snapshot.outputReceipt.nativeTextEnvironment,
                currentBindings: [active]
            )),
            .activeExactReprint
        )
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.derivedFamilies, ["AssetLabelGenerationPlanV1", "LabelProjectionResultV1"])
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("AssetLabelGenerationPlanV1"))
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("LabelProjectionResultV1"))
        XCTAssertEqual(LabelOutputDispositionV1.allCases, [.generated, .handedOffToSystem])
        XCTAssertEqual(Set(LabelReprintEligibilityV1.allCases), [.activeExactReprint, .historicExportOnly, .blockedMissingRelease])
        try await C45AssetLabelTestSupport.verifyRealBackupRestoreCloneAndFork(slot: 1_100)
        try await C45AssetLabelTestSupport.verifyRealErase(slot: 1_300)
    }
}

private enum C45AssetLabelTestSupport {
    struct Fixture: Sendable {
        let plan: AssetLabelGenerationPlanV1
        let locators: [AssetLocatorV1]
        let receipts: [LocatorBindingReceiptV1]
    }

    static func fixture(
        itemCount: Int,
        disclosure: LabelDisclosureProfileV1 = .assetAndShortCode,
        startOffset: Int = 0,
        workspaceID: WorkspaceID? = nil,
        assetDisplay: String? = nil,
        locationDisplay: String? = nil,
        templateProfile: AssetLabelTemplateProfileV1 = .letterOneByTwoAndFiveEighths
    ) throws -> Fixture {
        let workspaceID = workspaceID ?? workspace(10)
        let template = try AssetLabelTemplateCatalogV1.makeRelease(
            templateProfile
        )
        var items: [AssetLabelItemSnapshotV1] = []
        var locators: [AssetLocatorV1] = []
        var receipts: [LocatorBindingReceiptV1] = []
        for index in 0..<itemCount {
            let value = try item(
                index: index,
                workspaceID: workspaceID,
                templateDisclosure: disclosure,
                assetDisplay: assetDisplay,
                locationDisplay: locationDisplay
            )
            items.append(value.item); locators.append(value.locator); receipts.append(value.receipt)
        }
        return Fixture(
            plan: try AssetLabelGenerationPlanV1(
                planID: id(20),
                workspaceID: workspaceID,
                template: template,
                disclosure: disclosure,
                items: items,
                startOffset: startOffset,
                localeIdentifier: "en_US_POSIX",
                frozenGeneratedAt: date(20)
            ),
            locators: locators,
            receipts: receipts
        )
    }

    static func item(
        index: Int,
        workspaceID: WorkspaceID,
        templateDisclosure disclosure: LabelDisclosureProfileV1,
        assetDisplay override: String? = nil,
        locationDisplay locationOverride: String? = nil,
        orderIndex: Int? = nil
    ) throws -> (item: AssetLabelItemSnapshotV1, locator: AssetLocatorV1, receipt: LocatorBindingReceiptV1) {
        let shortCode = try ManualShortCodeV1(randomBody: body(index))
        let assetID = id(10_000 + index)
        let locator = try AssetLocatorV1(
            locatorID: id(20_000 + index),
            workspaceID: workspaceID,
            assetID: assetID,
            representation: .externalKey(shortCode.externalKey()),
            state: .active,
            revision: 1,
            mutationID: mutation(30_000 + index),
            recordedAt: date(Double(30_000 + index))
        )
        let actor = try actor(workspaceID: workspaceID, slot: 40_000 + index)
        let preview = try LocatorBindingPreviewV1(
            workspaceID: workspaceID,
            action: .bind,
            before: nil,
            after: locator.reference,
            replacement: nil,
            generatedAt: date(Double(50_000 + index))
        )
        let receipt = try LocatorBindingReceiptV1(
            receiptID: id(60_000 + index),
            preview: preview,
            recordedBy: actor,
            predecessor: nil,
            revision: 1,
            mutationID: mutation(70_000 + index),
            recordedAt: date(Double(50_001 + index))
        )
        let assetDisplay: String
        switch disclosure {
        case .shortCodeOnly: assetDisplay = shortCode.displayValue
        case .assetAndShortCode, .assetLocationAndShortCode:
            assetDisplay = override ?? (index == 0 ? "=SUM(1,1)" : "Boiler \(index + 1)")
        }
        let location = disclosure == .assetLocationAndShortCode
            ? (locationOverride ?? "Plant room \(index + 1)")
            : nil
        return (
            try AssetLabelItemSnapshotV1(
                workspaceID: workspaceID,
                assetID: assetID,
                assetRevision: 1,
                locator: locator,
                bindingReceipt: receipt,
                shortCode: shortCode,
                assetDisplay: assetDisplay,
                locationDisplay: location,
                disclosure: disclosure,
                orderIndex: orderIndex ?? index
            ),
            locator,
            receipt
        )
    }

    static func output(
        plan: AssetLabelGenerationPlanV1,
        result: LabelProjectionResultV1,
        slot: Int,
        publishedArtifacts suppliedArtifacts: [AssetLabelPublishedArtifactContentV1]? = nil,
        publicationReceipt suppliedReceipt: LocalJobPublicationReceiptV1? = nil
    ) throws -> LabelOutputReceiptV1 {
        let outputSHA256 = result.manifest.manifestSHA256
        let jobID = LocalJobIDV1.deterministic(
            kind: .render,
            workspaceID: plan.workspaceID.rawValue,
            immutableInputSHA256: plan.planSHA256
        )
        let publicationReceipt = suppliedReceipt ?? LocalJobPublicationReceiptV1(
            jobID: jobID,
            attemptCount: 1,
            kind: .render,
            outputSHA256: outputSHA256,
            disposition: .published,
            readBackAt: date(Double(slot))
        )
        let publishedArtifacts: [AssetLabelPublishedArtifactContentV1]
        if let suppliedArtifacts {
            publishedArtifacts = suppliedArtifacts
        } else {
            publishedArtifacts = try self.publishedArtifacts(
                plan: plan,
                result: result,
                slot: slot
            )
        }
        try LabelOutputReceiptV1(
            receiptID: id(slot),
            workspaceID: plan.workspaceID,
            planID: plan.planID,
            planSHA256: plan.planSHA256,
            manifestSHA256: result.manifest.manifestSHA256,
            nativeTextEnvironment: result.nativeTextEnvironment,
            publicationBinding: try AssetLabelRenderPublicationBindingV1(
                workspaceID: plan.workspaceID,
                planSHA256: plan.planSHA256,
                manifestSHA256: result.manifest.manifestSHA256,
                outputSHA256: outputSHA256,
                publishedArtifacts: publishedArtifacts,
                publicationReceipt: publicationReceipt
            ),
            disposition: .generated,
            generatedAt: date(Double(slot))
        )
    }

    static func publishedArtifacts(
        plan: AssetLabelGenerationPlanV1,
        result: LabelProjectionResultV1,
        slot: Int
    ) throws -> [AssetLabelPublishedArtifactContentV1] {
        _ = slot
        let workspace = plan.workspaceID.rawValue.uuidString.lowercased()
        let jobID = LocalJobIDV1.deterministic(
            kind: .render,
            workspaceID: plan.workspaceID.rawValue,
            immutableInputSHA256: plan.planSHA256
        ).rawValue.uuidString.lowercased()
        return try result.artifacts.map { artifact in
            let digest = try ContentDigestV1(
                algorithm: .sha256,
                hexadecimalValue: artifact.entry.sha256
            )
            let suffix: String
            switch artifact.entry.kind {
            case .pdf: suffix = "pdf"
            case .formulaSafeCSV: suffix = "csv"
            case .structuredText: suffix = "text"
            }
            let contentID = "asset-label-\(jobID)-\(suffix)"
            let reference = try ContentReferenceV1(
                workspaceID: workspace,
                contentID: contentID,
                byteLength: artifact.entry.byteCount,
                mediaType: artifact.entry.mediaType,
                digests: ContentDigestSetV1([digest]),
                byteRole: .derivative,
                createdAt: "2023-11-14T22:13:20.000Z"
            )
            let locator = try ContentLocatorV1(
                locatorID: "c05-\(contentID)",
                workspaceID: workspace,
                contentID: reference.contentID,
                locatorRevision: 1,
                contentDigest: digest,
                expectedByteLength: artifact.entry.byteCount
            )
            return try AssetLabelPublishedArtifactContentV1(
                kind: artifact.entry.kind,
                reference: reference,
                locator: locator
            )
        }
    }

    static func snapshot(
        fixture: Fixture,
        result: LabelProjectionResultV1,
        output: LabelOutputReceiptV1,
        slot: Int
    ) throws -> AcceptedLabelGenerationSnapshotV1 {
        let snapshotID = id(slot)
        return try AcceptedLabelGenerationSnapshotV1(
            snapshotID: snapshotID,
            plan: fixture.plan,
            result: result,
            outputReceipt: output,
            activationDecision: .enabledBoundedLocalOnly,
            expectedRevision: expectedRevision(
                workspaceID: fixture.plan.workspaceID,
                snapshotID: snapshotID,
                slot: slot + 1
            ),
            mutationID: mutation(slot + 2),
            recordedBy: actor(workspaceID: fixture.plan.workspaceID, slot: slot + 3),
            recordedAt: date(Double(slot + 4))
        )
    }

    static func verifyPublicationBindingAndOwnershipHostiles(slot: Int) throws {
        let fixture = try fixture(itemCount: 1)
        let projection = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let artifacts = try publishedArtifacts(plan: fixture.plan, result: projection, slot: slot)
        let output = try output(
            plan: fixture.plan,
            result: projection,
            slot: slot,
            publishedArtifacts: artifacts
        )
        let binding = output.publicationBinding
        try binding.validate(manifest: projection.manifest)
        let workspaceValue = fixture.plan.workspaceID.rawValue.uuidString.lowercased()

        func reference(
            from artifact: AssetLabelPublishedArtifactContentV1,
            contentID: String? = nil,
            digests: ContentDigestSetV1? = nil
        ) throws -> ContentReferenceV1 {
            try ContentReferenceV1(
                workspaceID: artifact.reference.workspaceID,
                contentID: contentID ?? artifact.reference.contentID,
                byteLength: artifact.reference.byteLength,
                mediaType: artifact.reference.mediaType,
                digests: digests ?? artifact.reference.digests,
                byteRole: artifact.reference.byteRole,
                createdAt: artifact.reference.createdAt
            )
        }

        func artifact(
            from original: AssetLabelPublishedArtifactContentV1,
            reference: ContentReferenceV1,
            locatorID: String? = nil,
            locatorRevision: Int = 1
        ) throws -> AssetLabelPublishedArtifactContentV1 {
            let digest = try XCTUnwrap(reference.digests.digest(for: .sha256))
            return try AssetLabelPublishedArtifactContentV1(
                kind: original.kind,
                reference: reference,
                locator: ContentLocatorV1(
                    locatorID: locatorID ?? "c05-\(reference.contentID)",
                    workspaceID: workspaceValue,
                    contentID: reference.contentID,
                    locatorRevision: locatorRevision,
                    contentDigest: digest,
                    expectedByteLength: reference.byteLength
                )
            )
        }

        func replacing(
            _ original: AssetLabelPublishedArtifactContentV1,
            with replacement: AssetLabelPublishedArtifactContentV1
        ) -> [AssetLabelPublishedArtifactContentV1] {
            artifacts.map { $0.kind == original.kind ? replacement : $0 }
        }

        func assertBindingRejects(
            _ candidates: [AssetLabelPublishedArtifactContentV1],
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertThrowsError(
                try AssetLabelRenderPublicationBindingV1(
                    workspaceID: fixture.plan.workspaceID,
                    planSHA256: fixture.plan.planSHA256,
                    manifestSHA256: projection.manifest.manifestSHA256,
                    outputSHA256: projection.manifest.manifestSHA256,
                    publishedArtifacts: candidates,
                    publicationReceipt: binding.publicationReceipt
                ),
                file: file,
                line: line
            ) {
                XCTAssertEqual($0 as? AssetLabelContractFailureV1, .invalidReceipt)
            }
        }

        let first = try XCTUnwrap(artifacts.first)
        let second = try XCTUnwrap(artifacts.dropFirst().first)
        let forgedContentID = "asset-label-\(binding.jobID.rawValue.uuidString.lowercased())-forged"
        let forgedReference = try reference(from: first, contentID: forgedContentID)
        assertBindingRejects(replacing(first, with: try artifact(from: first, reference: forgedReference)))
        assertBindingRejects(replacing(
            first,
            with: try artifact(
                from: first,
                reference: first.reference,
                locatorID: "c05-forged-\(first.reference.contentID)"
            )
        ))
        assertBindingRejects(replacing(
            first,
            with: try artifact(from: first, reference: first.reference, locatorRevision: 2)
        ))

        let sha256 = try XCTUnwrap(first.reference.digests.digest(for: .sha256))
        let sha512 = try ContentDigestV1(
            algorithm: .sha512,
            hexadecimalValue: String(repeating: "a", count: 128)
        )
        let multipleDigestReference = try reference(
            from: first,
            digests: ContentDigestSetV1([sha256, sha512])
        )
        assertBindingRejects(replacing(
            first,
            with: try artifact(from: first, reference: multipleDigestReference)
        ))

        let duplicateContentReference = try reference(
            from: second,
            contentID: first.reference.contentID
        )
        let duplicateContent = try artifact(
            from: second,
            reference: duplicateContentReference,
            locatorID: "c05-duplicate-content-\(second.kind.rawValue.lowercased())"
        )
        assertBindingRejects(replacing(second, with: duplicateContent))
        let duplicateLocator = try artifact(
            from: second,
            reference: second.reference,
            locatorID: first.locator.locatorID
        )
        assertBindingRejects(replacing(second, with: duplicateLocator))

        var nonSHAObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: AssetLabelCanonicalCodecV1.encode(binding)
            ) as? [String: Any]
        )
        var encodedArtifacts = try XCTUnwrap(nonSHAObject["publishedArtifacts"] as? [[String: Any]])
        var encodedReference = try XCTUnwrap(encodedArtifacts[0]["reference"] as? [String: Any])
        encodedReference["digests"] = [
            "values": [["algorithm": "SHA512", "hexadecimalValue": String(repeating: "b", count: 128)]]
        ]
        encodedArtifacts[0]["reference"] = encodedReference
        nonSHAObject["publishedArtifacts"] = encodedArtifacts
        let nonSHAData = try JSONSerialization.data(withJSONObject: nonSHAObject, options: [.sortedKeys])
        XCTAssertThrowsError(
            try AssetLabelCanonicalCodecV1.decode(
                AssetLabelRenderPublicationBindingV1.self,
                from: nonSHAData
            )
        )

        let firstSnapshot = try snapshot(
            fixture: fixture,
            result: projection,
            output: output,
            slot: slot + 10
        )
        let identicalReplay = try snapshot(
            fixture: fixture,
            result: projection,
            output: output,
            slot: slot + 20
        )
        XCTAssertEqual(
            try backupRecords(
                snapshots: [firstSnapshot, identicalReplay],
                mutationSources: [firstSnapshot, identicalReplay]
            ).validateC45AcceptedLabelSnapshots(),
            [firstSnapshot, identicalReplay]
        )

        let conflictingPublicationReceipt = LocalJobPublicationReceiptV1(
            jobID: binding.jobID,
            attemptCount: binding.publicationReceipt.attemptCount + 1,
            kind: .render,
            outputSHA256: binding.outputSHA256,
            disposition: .adopted,
            readBackAt: date(Double(slot + 30))
        )
        let conflictingOutput = try output(
            plan: fixture.plan,
            result: projection,
            slot: slot + 30,
            publishedArtifacts: artifacts,
            publicationReceipt: conflictingPublicationReceipt
        )
        let conflictingSnapshot = try snapshot(
            fixture: fixture,
            result: projection,
            output: conflictingOutput,
            slot: slot + 40
        )
        XCTAssertThrowsError(try backupRecords(
            snapshots: [firstSnapshot, conflictingSnapshot],
            mutationSources: [firstSnapshot, conflictingSnapshot]
        ).validateC45AcceptedLabelSnapshots()) {
            XCTAssertEqual($0 as? AssetLabelContractFailureV1, .duplicateIdentity)
        }

        let historicWorkspace = workspace(slot + 50)
        let historicConflict = try conflictingSnapshot.rebound(
            to: historicWorkspace,
            expectedRevision: expectedRevision(
                workspaceID: historicWorkspace,
                snapshotID: conflictingSnapshot.snapshotID,
                slot: slot + 51
            ),
            mutationID: mutation(slot + 52),
            recordedBy: actor(workspaceID: historicWorkspace, slot: slot + 53),
            recordedAt: conflictingSnapshot.recordedAt
        )
        XCTAssertEqual(
            try backupRecords(
                snapshots: [firstSnapshot, historicConflict],
                mutationSources: [firstSnapshot, conflictingSnapshot]
            ).validateC45AcceptedLabelSnapshots(),
            [firstSnapshot, historicConflict]
        )
    }

    static func backupRecords(
        snapshots: [AcceptedLabelGenerationSnapshotV1],
        mutationSources: [AcceptedLabelGenerationSnapshotV1]
    ) throws -> V4BackupRecordsV1 {
        let history = try mutationSources.enumerated().map { index, snapshot in
            let replicaID = ReplicaID(rawValue: id(95_000 + index))
            let receipt = try canonicalReceipt(snapshot: snapshot, replicaID: replicaID)
            let mutation = try AssetLabelMutationV1(snapshot: snapshot)
            return MutationHistoryReceiptRecordV1(
                envelopeData: try MutationEnvelopeV1(
                    request: mutation.canonicalWorkspaceMutationRequest(),
                    identity: WorkspaceReplicaIdentityV1(
                        workspaceID: snapshot.workspaceID,
                        replicaID: replicaID
                    )
                ).canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: nil,
                semanticReversalData: nil
            )
        }
        return V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [],
            mutationHistory: MutationHistorySnapshotV1(
                workspaceRevision: UInt64(history.count),
                lastLocalSequence: UInt64(history.count),
                receipts: history,
                quarantines: [],
                entityRevisions: []
            ),
            packets: [],
            recordsSchemaVersion: AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [],
            acceptedLabelGenerationSnapshots: try snapshots.map(V34BackupAcceptedLabelSnapshotRecordV1.init)
        )
    }

    static func currentBinding(
        item: AssetLabelItemSnapshotV1,
        state: AssetLocatorStateV1 = .active,
        assetRevision: UInt64? = nil,
        bindingRevision: UInt64? = nil
    ) throws -> AssetLabelCurrentBindingV1 {
        let value = AssetLabelCurrentBindingV1(
            assetID: item.assetID,
            assetRevision: assetRevision ?? item.assetRevision,
            locator: item.locator,
            locatorState: state,
            bindingReceiptID: item.bindingReceiptID,
            bindingReceiptRevision: bindingRevision ?? item.bindingReceiptRevision,
            bindingReceiptSHA256: item.bindingReceiptSHA256
        )
        try value.validate()
        return value
    }

    static func canonicalReceipt(
        snapshot: AcceptedLabelGenerationSnapshotV1,
        replicaID: ReplicaID = ReplicaID(rawValue: id(90_001))
    ) throws -> MutationReceiptV1 {
        let mutation = try AssetLabelMutationV1(snapshot: snapshot)
        let replica = try WorkspaceReplicaIdentityV1(
            workspaceID: snapshot.workspaceID,
            replicaID: replicaID
        )
        let envelope = try MutationEnvelopeV1(
            request: mutation.canonicalWorkspaceMutationRequest(),
            identity: replica
        )
        let postImage = try mutation.mutationPostImage
        let resulting = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: snapshot.workspaceID,
                generationID: snapshot.expectedRevision.generationID,
                writerInstanceID: snapshot.expectedRevision.writerInstanceID,
                workspaceRevision: snapshot.expectedRevision.workspaceRevision + 1,
                entityRevisions: [
                    WorkspaceEntityRevisionV1(
                        identity: try mutation.affectedIdentity,
                        revision: snapshot.revision
                    )
                ]
            )
        )
        return try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: snapshot.workspaceID,
                replicaID: replicaID,
                localSequence: 1
            ),
            envelope: envelope,
            resultingRevision: resulting,
            postImages: [postImage],
            committedAt: snapshot.recordedAt.addingTimeInterval(1)
        )
    }

    @MainActor
    static func verifyRealShortCodeIssuanceRecovery(slot: Int) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C45-I01-Issuance-\(slot)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let session = try StoreGenerationFactory(
            applicationSupportURL: root
        ).openOrBootstrapCurrent()
        let fixture = try fixture(itemCount: 2, workspaceID: session.workspaceID)
        let siteID = id(slot + 1)
        session.modelContext.insert(Site(
            id: siteID,
            label: "C45 issuer site",
            createdAt: date(Double(slot + 1))
        ))
        for item in fixture.plan.items {
            session.modelContext.insert(Asset(
                id: item.assetID,
                siteID: siteID,
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                label: "C45 issuer asset",
                createdAt: date(Double(slot + 2))
            ))
        }
        let collidingLocator = fixture.locators[0]
        XCTAssertEqual(fixture.plan.items[0].shortCode.randomBody, "2222222222")
        session.modelContext.insert(try AssetLocatorRow(collidingLocator))
        let historicCodesAndStates: [(ManualShortCodeV1, AssetLocatorStateV1)] = try [
            (ManualShortCodeV1(randomBody: "3333333333"), .retired),
            (ManualShortCodeV1(randomBody: "4444444444"), .revoked),
            (ManualShortCodeV1(randomBody: "5555555555"), .replaced),
        ]
        var historicLocators: [AssetLocatorV1] = []
        for (index, pair) in historicCodesAndStates.enumerated() {
            let replacementID = pair.1 == .replaced ? id(slot + 80 + index) : nil
            let historic = try AssetLocatorV1(
                locatorID: id(slot + 75 + index),
                workspaceID: session.workspaceID,
                assetID: fixture.plan.items[0].assetID,
                representation: .externalKey(pair.0.externalKey()),
                state: pair.1,
                replacedByLocatorID: replacementID,
                revision: 1,
                mutationID: mutation(slot + 75 + index),
                recordedAt: date(Double(slot + 75 + index))
            )
            historicLocators.append(historic)
            session.modelContext.insert(try AssetLocatorRow(historic))
        }
        let issuanceActor = try actor(
            workspaceID: session.workspaceID,
            slot: slot + 8
        )
        session.modelContext.insert(try ActorSnapshotRow(issuanceActor))
        try session.modelContext.save()

        let journal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let writerInstanceID = id(slot + 3)
        func makeWriter() throws -> WorkspaceWriterV1 {
            try WorkspaceWriterV1(
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                initialRevision: journal.currentRevision(writerInstanceID: writerInstanceID),
                clock: C45ApplicationClock(value: date(Double(slot + 4))),
                idSource: C45ApplicationIDSource(value: writerInstanceID),
                fileAuthority: C45ApplicationFileAuthority(),
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
                journalStore: journal
            )
        }
        let operation = try ManualShortCodeIssuanceOperationV1(
            workspaceID: session.workspaceID,
            assetID: fixture.plan.items[1].assetID,
            locatorID: id(slot + 5),
            bindingReceiptID: id(slot + 6),
            mutationID: mutation(slot + 7),
            recordedBy: issuanceActor,
            requestedAt: date(Double(slot + 9))
        )
        let unprovedCode = try ManualShortCodeV1(randomBody: "ZZZZZZZZZZ")
        let unprovedMutationID = try mutation(slot + 70)
        let unprovedLocator = try AssetLocatorV1(
            locatorID: id(slot + 71),
            workspaceID: session.workspaceID,
            assetID: fixture.plan.items[1].assetID,
            representation: .externalKey(unprovedCode.externalKey()),
            state: .active,
            revision: 1,
            mutationID: unprovedMutationID,
            recordedAt: date(Double(slot + 72))
        )
        let unprovedPreview = try LocatorBindingPreviewV1(
            workspaceID: session.workspaceID,
            action: .bind,
            before: nil,
            after: unprovedLocator.reference,
            replacement: nil,
            generatedAt: date(Double(slot + 72))
        )
        let unprovedReceipt = try LocatorBindingReceiptV1(
            receiptID: id(slot + 73),
            preview: unprovedPreview,
            recordedBy: issuanceActor,
            predecessor: nil,
            revision: 1,
            mutationID: unprovedMutationID,
            recordedAt: date(Double(slot + 72)),
            manualShortCodeIssuance: nil
        )
        XCTAssertThrowsError(try AssetLocatorMutationV1(
            workspaceID: session.workspaceID,
            mutationID: unprovedMutationID,
            payload: .bind(
                unprovedLocator,
                receipt: unprovedReceipt,
                predecessorReceipt: nil
            )
        )) {
            XCTAssertEqual($0 as? WorkspaceMutationContractFailureV1, .invalidPlan)
        }
        let entropy = C45DeterministicShortCodeEntropy(values: [
            Data(repeating: 0, count: ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt),
            Data(repeating: 1, count: ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt),
            Data(repeating: 2, count: ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt),
            Data(repeating: 3, count: ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt),
            Data(repeating: 4, count: ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt),
        ])
        let query = AssetLocatorRowQueryV1(modelContext: session.modelContext)
        let historicResolver = OfflineAssetLocatorResolverV1(
            query: query,
            signatureVerifier: C45RejectingSignatureVerifier()
        )
        for (locator, pair) in zip(historicLocators, historicCodesAndStates) {
            let key = try pair.0.externalKey()
            let resolution = try await historicResolver.resolve(
                LocatorResolutionInputV1(
                    source: .manual,
                    rawBytes: Data(pair.0.canonicalLocatorValue.utf8),
                    decoded: .externalKey(key)
                ),
                workspaceID: session.workspaceID,
                evaluatedAt: date(Double(slot + 79))
            )
            let expectedOutcome: LocatorResolutionOutcomeV1
            switch pair.1 {
            case .retired: expectedOutcome = .retired
            case .revoked: expectedOutcome = .revoked
            case .replaced: expectedOutcome = .replaced
            case .active: XCTFail("Historic reuse fixture must not be active"); continue
            }
            XCTAssertEqual(resolution.outcome, expectedOutcome)
            XCTAssertEqual(resolution.matchedLocator, try locator.reference)
            XCTAssertEqual(resolution.matchedAssetID, locator.assetID)
        }
        let availabilityWriter = try makeWriter()
        let preparingCoordinator = ManualShortCodeIssuanceCoordinatorV1(
            query: query,
            writer: availabilityWriter,
            entropy: entropy
        )

        let prepared = try await preparingCoordinator.prepare(operation)
        XCTAssertEqual(prepared.shortCode.randomBody, "6666666666")
        XCTAssertEqual(entropy.requestCount, 5)
        XCTAssertNil(try journal.receipt(mutationID: operation.mutationID))
        let beforeIssuanceLocator = try await query.locator(
            id: operation.locatorID,
            workspaceID: operation.workspaceID
        )
        XCTAssertNil(beforeIssuanceLocator)

        let resumedBeforeReceipt = ManualShortCodeIssuanceCoordinatorV1(
            query: query,
            writer: try makeWriter(),
            entropy: C45DeterministicShortCodeEntropy(values: [])
        )
        let issued = try await resumedBeforeReceipt.issue(prepared)
        try issued.validate()
        XCTAssertEqual(issued.request, prepared)
        XCTAssertEqual(issued.locator.representation, .externalKey(try prepared.shortCode.externalKey()))
        XCTAssertEqual(issued.bindingReceipt.action, .bind)
        XCTAssertEqual(issued.bindingReceipt.workspaceID, operation.workspaceID)
        XCTAssertEqual(issued.bindingReceipt.mutationID, operation.mutationID)
        XCTAssertEqual(issued.bindingReceipt.after, try issued.locator.reference)
        XCTAssertEqual(issued.bindingReceipt.manualShortCodeIssuance, prepared.shortCode)
        let persistedLocator = try await query.locator(
            id: operation.locatorID,
            workspaceID: operation.workspaceID
        )
        XCTAssertEqual(persistedLocator, issued.locator)
        XCTAssertNotNil(try journal.receipt(mutationID: operation.mutationID))
        XCTAssertFalse(try makeWriter().manualShortCodeIsAvailable(
            issued.request.shortCode,
            workspaceID: session.workspaceID
        ))

        let resumedAfterReceipt = ManualShortCodeIssuanceCoordinatorV1(
            query: query,
            writer: try makeWriter(),
            entropy: C45DeterministicShortCodeEntropy(values: [])
        )
        let replayed = try await resumedAfterReceipt.issue(prepared)
        XCTAssertEqual(replayed, issued)
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<AssetLocatorRow>()).count,
            5
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>()).count,
            1
        )
        let operationReplay = try await resumedAfterReceipt.issue(operation)
        XCTAssertEqual(operationReplay, issued)
        let recoveredBinding = try await query.bindingReceipt(
            id: operation.bindingReceiptID,
            workspaceID: operation.workspaceID
        )
        let persistedBinding = try XCTUnwrap(recoveredBinding)
        XCTAssertEqual(
            persistedBinding.manualShortCodeIssuance,
            issued.request.shortCode
        )
    }

    @MainActor
    static func verifyEvidenceBundlePublicationRecovery(slot: Int) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C45-I01-Content-\(slot)-\(UUID().uuidString)",
            isDirectory: true
        )
        let generationRoot = root.appendingPathComponent("generation", isDirectory: true)
        let ledgerRoot = root.appendingPathComponent("ledger", isDirectory: true)
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        try fileManager.createDirectory(at: generationRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let epoch = try GenerationEpochV1(
            generationID: id(slot + 1),
            generationManifestSHA256: digest("c")
        )
        let publicationAdapter = GenerationLocalJobPublicationAdapterV1(
            currentGenerationEpoch: { epoch },
            withAuthorizedCommit: { expected, effect in
                guard expected == epoch else {
                    throw GenerationLocalJobPublicationFailureV1.staleGeneration
                }
                return try effect()
            }
        )
        let fixture = try fixture(itemCount: 2, workspaceID: workspace(slot + 2))
        let projection = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let injection = EvidenceBundleStoreFailureInjection(
            failOnceAt: .assetLabelPublicationBeforeMarkerCommit
        )
        let interruptedContentStore = EvidenceBundleStore(
            generationRootURL: generationRoot,
            failureInjection: injection
        )
        let interruptedOperations = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: stagingRoot,
            contentStore: interruptedContentStore
        )
        let interruptedRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: ledgerRoot),
            stagingRootURL: stagingRoot,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let authority = AssetLabelAuthoritativePlanAdapterV1 { try $0.validate() }
        let writer = C45AcceptingWriter()
        let interruptedLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: writer,
            query: C45AcceptedSnapshotQuery(),
            jobs: interruptedRunner,
            artifacts: interruptedOperations
        )
        let job = try await interruptedLifecycle.enqueueValidatedPlan(
            fixture.plan,
            generationEpoch: epoch,
            createdAt: date(Double(slot + 3))
        )
        await interruptedRunner.waitUntilIdle()
        let interruptedJob = try await interruptedRunner.job(id: job.id)
        XCTAssertEqual(interruptedJob?.state, .awaitingPublication)
        XCTAssertNil(try interruptedContentStore.readAssetLabelArtifacts(jobID: job.id))

        let contentStore = EvidenceBundleStore(generationRootURL: generationRoot)
        let recoveredOperations = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: stagingRoot,
            contentStore: contentStore
        )
        let recoveredRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: ledgerRoot),
            stagingRootURL: stagingRoot,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let recoveredLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: writer,
            query: C45AcceptedSnapshotQuery(),
            jobs: recoveredRunner,
            artifacts: recoveredOperations
        )
        try await recoveredLifecycle.recoverAfterInterruption()
        await recoveredRunner.waitUntilIdle()
        let recoveredJobValue = try await recoveredRunner.job(id: job.id)
        let recoveredJob = try XCTUnwrap(recoveredJobValue)
        XCTAssertEqual(recoveredJob.state, .succeeded)
        let readback = try XCTUnwrap(
            try contentStore.readAssetLabelArtifacts(jobID: job.id)
        )
        XCTAssertEqual(readback.plan, fixture.plan)
        XCTAssertEqual(readback.projection, projection)
        XCTAssertEqual(readback.publishedArtifacts.count, LabelArtifactKindV1.allCases.count)
        XCTAssertEqual(
            try contentStore.adoptAssetLabelArtifacts(
                jobID: job.id,
                planSHA256: fixture.plan.planSHA256,
                outputSHA256: projection.manifest.manifestSHA256
            ),
            readback
        )
        XCTAssertThrowsError(try contentStore.adoptAssetLabelArtifacts(
            jobID: job.id,
            planSHA256: fixture.plan.planSHA256,
            outputSHA256: digest("f")
        )) {
            XCTAssertEqual($0 as? EvidenceBundleStoreError, .bundleFactsMismatch)
        }

        let unrelated = try fixture(itemCount: 1, workspaceID: workspace(slot + 20))
        let unrelatedProjection = try DeterministicPDFRendererV1.renderAssetLabels(unrelated.plan)
        let unrelatedJob = try await recoveredLifecycle.enqueueValidatedPlan(
            unrelated.plan,
            generationEpoch: epoch,
            createdAt: date(Double(slot + 21))
        )
        await recoveredRunner.waitUntilIdle()
        let completedUnrelatedJob = try await recoveredRunner.job(id: unrelatedJob.id)
        XCTAssertEqual(completedUnrelatedJob?.state, .succeeded)
        let unrelatedReadback = try XCTUnwrap(
            try contentStore.readAssetLabelArtifacts(jobID: unrelatedJob.id)
        )
        XCTAssertEqual(unrelatedReadback.plan, unrelated.plan)
        XCTAssertEqual(unrelatedReadback.projection, unrelatedProjection)

        let publicationReceipt = try XCTUnwrap(recoveredJob.publicationReceipt)
        let binding = try AssetLabelRenderPublicationBindingV1(
            workspaceID: fixture.plan.workspaceID,
            planSHA256: fixture.plan.planSHA256,
            manifestSHA256: projection.manifest.manifestSHA256,
            outputSHA256: projection.manifest.manifestSHA256,
            publishedArtifacts: readback.publishedArtifacts,
            publicationReceipt: publicationReceipt
        )
        try binding.validate(manifest: projection.manifest)
        try contentStore.removeAssetLabelPublishedOutput(binding)
        XCTAssertNil(try contentStore.readAssetLabelArtifacts(jobID: job.id))
        try contentStore.removeAssetLabelPublishedOutput(binding)
        XCTAssertEqual(
            try contentStore.readAssetLabelArtifacts(jobID: unrelatedJob.id),
            unrelatedReadback
        )

        let cancelledFixture = try fixture(
            itemCount: 1,
            workspaceID: workspace(slot + 40)
        )
        let cancelledProjection = try DeterministicPDFRendererV1.renderAssetLabels(
            cancelledFixture.plan
        )
        let cancelledLedgerRoot = root.appendingPathComponent(
            "cancelled-ledger",
            isDirectory: true
        )
        let cancelledStagingRoot = root.appendingPathComponent(
            "cancelled-staging",
            isDirectory: true
        )
        let cancellationInjection = EvidenceBundleStoreFailureInjection(
            failOnceAt: .assetLabelPublicationBeforeMarkerCommit
        )
        let cancellationStore = EvidenceBundleStore(
            generationRootURL: generationRoot,
            failureInjection: cancellationInjection
        )
        let cancelledOperations = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: cancelledStagingRoot,
            contentStore: cancellationStore
        )
        let cancelledRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: cancelledLedgerRoot),
            stagingRootURL: cancelledStagingRoot,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let cancelledLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: writer,
            query: C45AcceptedSnapshotQuery(),
            jobs: cancelledRunner,
            artifacts: cancelledOperations
        )
        let cancelledJob = try await cancelledLifecycle.enqueueValidatedPlan(
            cancelledFixture.plan,
            generationEpoch: epoch,
            createdAt: date(Double(slot + 41))
        )
        await cancelledRunner.waitUntilIdle()
        let failedCancellationJob = try await cancelledRunner.job(id: cancelledJob.id)
        XCTAssertEqual(failedCancellationJob?.state, .awaitingPublication)

        let coldCancellationOperations = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: cancelledStagingRoot,
            contentStore: contentStore
        )
        let coldCancellationRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: cancelledLedgerRoot),
            stagingRootURL: cancelledStagingRoot,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let coldCancellationLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: writer,
            query: C45AcceptedSnapshotQuery(),
            jobs: coldCancellationRunner,
            artifacts: coldCancellationOperations
        )
        try await coldCancellationLifecycle.cancelOrExpire(jobID: cancelledJob.id)
        await coldCancellationRunner.waitUntilIdle()
        try await coldCancellationLifecycle.recoverAfterInterruption()
        await coldCancellationRunner.waitUntilIdle()
        let recoveredCancellationJob = try await coldCancellationRunner.job(
            id: cancelledJob.id
        )
        XCTAssertEqual(recoveredCancellationJob?.state, .cancelled)
        XCTAssertNil(try contentStore.readAssetLabelArtifacts(jobID: cancelledJob.id))
        let cancelledScratch = try await coldCancellationOperations.load(
            cancelledJob.id,
            cancelledFixture.plan.planSHA256
        )
        XCTAssertNil(cancelledScratch)
        let cancelledWorkspace = cancelledFixture.plan.workspaceID.rawValue.uuidString.lowercased()
        for kind in LabelArtifactKindV1.allCases {
            let suffix: String
            switch kind {
            case .pdf: suffix = "pdf"
            case .formulaSafeCSV: suffix = "csv"
            case .structuredText: suffix = "text"
            }
            let contentID = "asset-label-\(cancelledJob.id.rawValue.uuidString.lowercased())-\(suffix)"
            let orphan = generationRoot.appendingPathComponent(
                "content/\(cancelledWorkspace)/\(contentID)",
                isDirectory: true
            )
            XCTAssertFalse(fileManager.fileExists(atPath: orphan.path))
        }
        XCTAssertEqual(
            try DeterministicPDFRendererV1.renderAssetLabels(cancelledFixture.plan),
            cancelledProjection
        )
    }

    @MainActor
    static func verifyResumableRunnerRelaunch(slot: Int) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C45-I01-\(slot)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let ledgerRoot = root.appendingPathComponent("ledger", isDirectory: true)
        let stagingRoot = root.appendingPathComponent("runner-staging", isDirectory: true)
        let publishedURL = root.appendingPathComponent("published-manifest.sha256")
        let epoch = try GenerationEpochV1(
            generationID: id(slot + 1),
            generationManifestSHA256: digest("e")
        )
        let fixture = try fixture(itemCount: 1)
        let projection = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let publication = C45PublicationProbe(url: publishedURL)
        let operations = try AssetLabelArtifactOperationsV1.durableStaging(
            jobStagingRootURL: stagingRoot,
            publishOrAdopt: { job, _, outputSHA256 in
                try publication.publishThenInterruptOnce(jobID: job.id, outputSHA256: outputSHA256)
            },
            adoptOnly: { job, _, outputSHA256 in
                try publication.adopt(jobID: job.id, outputSHA256: outputSHA256)
            },
            publishedReadback: { _, planSHA256, outputSHA256 in
                guard planSHA256 == fixture.plan.planSHA256,
                      outputSHA256 == projection.manifest.manifestSHA256 else { return nil }
                return AssetLabelPublishedContentReadbackV1(
                    plan: fixture.plan,
                    projection: projection,
                    publishedArtifacts: try publishedArtifacts(
                        plan: fixture.plan,
                        result: projection,
                        slot: slot + 30
                    )
                )
            },
            removePublishedOutput: { _ in },
            removePublishedWorkspace: { workspaceID in
                publication.remove(workspaceID: workspaceID)
            },
            eraseAllPublished: { publication.eraseAll() },
            discardUncommitted: { _ in }
        )
        let publicationAdapter = GenerationLocalJobPublicationAdapterV1(
            currentGenerationEpoch: { epoch },
            withAuthorizedCommit: { expected, effect in
                guard expected == epoch else {
                    throw GenerationLocalJobPublicationFailureV1.staleGeneration
                }
                return try effect()
            }
        )
        let firstRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: ledgerRoot),
            stagingRootURL: stagingRoot,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let authority = AssetLabelAuthoritativePlanAdapterV1 { plan in
            try plan.validate()
        }
        let canonicalWriter = C45AcceptingWriter()
        let firstLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: canonicalWriter,
            query: C45AcceptedSnapshotQuery(),
            jobs: firstRunner,
            artifacts: operations
        )
        let job = try await firstLifecycle.enqueueValidatedPlan(
            fixture.plan,
            generationEpoch: epoch,
            createdAt: date(Double(slot + 2))
        )
        await firstRunner.waitUntilIdle()
        let interruptedJob = try await firstRunner.job(id: job.id)
        XCTAssertEqual(interruptedJob?.state, .awaitingPublication)
        XCTAssertEqual(publication.effectCount, 1)

        let relaunchedRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: ledgerRoot),
            stagingRootURL: stagingRoot,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let relaunchedLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: canonicalWriter,
            query: C45AcceptedSnapshotQuery(),
            jobs: relaunchedRunner,
            artifacts: operations
        )
        try await relaunchedLifecycle.recoverAfterInterruption()
        await relaunchedRunner.waitUntilIdle()
        let recoveredJob = try await relaunchedRunner.job(id: job.id)
        XCTAssertEqual(recoveredJob?.state, .succeeded)
        XCTAssertEqual(publication.effectCount, 1)
        XCTAssertEqual(try String(contentsOf: publishedURL, encoding: .utf8), publication.outputSHA256)
        let acceptedSnapshotID = id(slot + 20)
        let acceptedExpectedRevision = try expectedRevision(
            workspaceID: fixture.plan.workspaceID,
            snapshotID: acceptedSnapshotID,
            slot: slot + 21
        )
        let acceptedMutationID = try mutation(slot + 22)
        let acceptedActor = try actor(
            workspaceID: fixture.plan.workspaceID,
            slot: slot + 23
        )
        let acceptedAt = date(Double(slot + 24))
        let acceptance = try await relaunchedLifecycle.acceptPublishedJob(
            jobID: job.id,
            outputReceiptID: id(slot + 19),
            snapshotID: acceptedSnapshotID,
            expectedRevision: acceptedExpectedRevision,
            mutationID: acceptedMutationID,
            recordedBy: acceptedActor,
            recordedAt: acceptedAt
        )
        let acceptedSnapshot = try XCTUnwrap(canonicalWriter.lastSnapshot)
        try acceptance.validate(snapshot: acceptedSnapshot)
        XCTAssertEqual(acceptedSnapshot.outputReceipt.publicationBinding.jobID, job.id)
        XCTAssertEqual(
            acceptedSnapshot.outputReceipt.publicationBinding.publicationReceipt,
            recoveredJob?.publicationReceipt
        )
        let replayedAcceptance = try await relaunchedLifecycle.acceptPublishedJob(
            jobID: job.id,
            outputReceiptID: id(slot + 19),
            snapshotID: acceptedSnapshotID,
            expectedRevision: acceptedExpectedRevision,
            mutationID: acceptedMutationID,
            recordedBy: acceptedActor,
            recordedAt: acceptedAt
        )
        XCTAssertEqual(replayedAcceptance, acceptance)
        XCTAssertEqual(canonicalWriter.commitCount, 1)
        try await relaunchedLifecycle.deleteWorkspaceArtifacts(
            workspaceID: fixture.plan.workspaceID
        )
        let removedJob = try await relaunchedRunner.job(id: job.id)
        let removedScratch = try await operations.load(job.id, fixture.plan.planSHA256)
        XCTAssertNil(removedJob)
        XCTAssertNil(removedScratch)
        XCTAssertEqual(publication.workspaceRemovalCount, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: publishedURL.path))
        try await relaunchedLifecycle.eraseAllArtifacts()
        XCTAssertEqual(publication.eraseCount, 1)
    }

    @MainActor
    static func verifyRealBackupRestoreCloneAndFork(slot: Int) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C45-R01-\(slot)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let sourceSupport = root.appendingPathComponent("source-support", isDirectory: true)
        try fileManager.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let sourceSession = try StoreGenerationFactory(
            applicationSupportURL: sourceSupport
        ).openOrBootstrapCurrent()
        let fixture = try fixture(itemCount: 3, workspaceID: sourceSession.workspaceID)
        let projection = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let contentStore = EvidenceBundleStore(
            generationRootURL: sourceSession.generationRootURL
        )
        let contentStagingRoot = sourceSession.generationRootURL.appendingPathComponent(
            "jobs",
            isDirectory: true
        )
        let contentOperations = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: contentStagingRoot,
            contentStore: contentStore
        )
        let contentEpoch = try GenerationEpochV1(
            generationID: sourceSession.generationID,
            generationManifestSHA256: digest("d")
        )
        let contentPublicationAdapter = GenerationLocalJobPublicationAdapterV1(
            currentGenerationEpoch: { contentEpoch },
            withAuthorizedCommit: { expected, effect in
                guard expected == contentEpoch else {
                    throw GenerationLocalJobPublicationFailureV1.staleGeneration
                }
                return try effect()
            }
        )
        let contentRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(
                applicationSupportURL: root.appendingPathComponent(
                    "source-label-job-ledger",
                    isDirectory: true
                )
            ),
            stagingRootURL: contentStagingRoot,
            generationPublicationAdapter: contentPublicationAdapter,
            maximumConcurrency: 1
        )
        let contentLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: AssetLabelAuthoritativePlanAdapterV1 { try $0.validate() },
            writer: C45AcceptingWriter(),
            query: C45AcceptedSnapshotQuery(),
            jobs: contentRunner,
            artifacts: contentOperations
        )
        let publishedJob = try await contentLifecycle.enqueueValidatedPlan(
            fixture.plan,
            generationEpoch: contentEpoch,
            createdAt: date(Double(slot + 1))
        )
        await contentRunner.waitUntilIdle()
        let publishedJobValue = try await contentRunner.job(id: publishedJob.id)
        let completedPublishedJob = try XCTUnwrap(publishedJobValue)
        XCTAssertEqual(completedPublishedJob.state, .succeeded)
        let publishedReadback = try XCTUnwrap(
            try contentStore.readAssetLabelArtifacts(jobID: publishedJob.id)
        )
        XCTAssertEqual(publishedReadback.plan, fixture.plan)
        XCTAssertEqual(publishedReadback.projection, projection)
        let output = try output(
            plan: fixture.plan,
            result: projection,
            slot: slot + 1,
            publishedArtifacts: publishedReadback.publishedArtifacts,
            publicationReceipt: try XCTUnwrap(completedPublishedJob.publicationReceipt)
        )
        let snapshotID = id(slot + 2)
        let writerInstanceID = id(slot + 3)
        let journal = try MutationJournalStoreV1(
            modelContext: sourceSession.modelContext,
            identity: sourceSession.workspaceIdentity,
            generationID: sourceSession.generationID
        )
        let current = try journal.currentRevision(writerInstanceID: writerInstanceID)
        let snapshot = try AcceptedLabelGenerationSnapshotV1(
            snapshotID: snapshotID,
            plan: fixture.plan,
            result: projection,
            outputReceipt: output,
            activationDecision: .enabledBoundedLocalOnly,
            expectedRevision: try WorkspaceExpectedRevisionV1(
                workspaceID: sourceSession.workspaceID,
                generationID: current.generationID,
                writerInstanceID: current.writerInstanceID,
                workspaceRevision: current.revision,
                entityRevisions: [
                    WorkspaceEntityRevisionV1(
                        identity: WorkspaceEntityIdentityV1(
                            kind: .acceptedLabelGenerationSnapshot,
                            id: snapshotID
                        ),
                        revision: 0
                    )
                ]
            ),
            mutationID: mutation(slot + 4),
            recordedBy: actor(workspaceID: sourceSession.workspaceID, slot: slot + 5),
            recordedAt: date(Double(slot + 6))
        )
        let mutation = try AssetLabelMutationV1(snapshot: snapshot)
        let receipt = try canonicalReceipt(
            snapshot: snapshot,
            replicaID: sourceSession.workspaceIdentity.replicaID
        )
        let envelope = try MutationEnvelopeV1(
            request: mutation.canonicalWorkspaceMutationRequest(),
            identity: sourceSession.workspaceIdentity
        )
        let siteID = id(slot + 8)
        sourceSession.modelContext.insert(Site(
            id: siteID,
            label: "C45 source site",
            createdAt: date(Double(slot + 8))
        ))
        for ((item, locator), bindingReceipt) in zip(
            zip(fixture.plan.items, fixture.locators),
            fixture.receipts
        ) {
            sourceSession.modelContext.insert(Asset(
                id: item.assetID,
                siteID: siteID,
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                label: "C45 asset",
                createdAt: date(Double(slot + 9))
            ))
            sourceSession.modelContext.insert(try AssetLocatorRow(locator))
            sourceSession.modelContext.insert(try LocatorBindingReceiptRow(bindingReceipt))
        }
        sourceSession.modelContext.insert(try AcceptedLabelGenerationSnapshotRow(snapshot))
        try journal.replaceHistory(
            with: MutationHistorySnapshotV1(
                workspaceRevision: 1,
                lastLocalSequence: 1,
                receipts: [MutationHistoryReceiptRecordV1(
                    envelopeData: try envelope.canonicalData(),
                    receiptData: try receipt.canonicalData(),
                    reversalBasisData: nil,
                    semanticReversalData: nil
                )],
                quarantines: [],
                entityRevisions: [MutationHistoryEntityRevisionV1(
                    identity: try mutation.affectedIdentity,
                    revision: snapshot.revision,
                    externalProjectionSHA256: snapshot.snapshotSHA256
                )]
            ),
            identityDisposition: .preserve
        )
        try sourceSession.modelContext.save()
        try journal.validateAll()
        let sourceAcceptance = try XCTUnwrap(
            journal.assetLabelAcceptanceReceipt(mutationID: snapshot.mutationID)
        )
        try sourceAcceptance.validate(snapshot: snapshot)
        XCTAssertEqual(sourceAcceptance.snapshotSHA256, snapshot.snapshotSHA256)
        XCTAssertEqual(sourceAcceptance.mutationSHA256, mutation.mutationSHA256)
        XCTAssertEqual(
            try journal.assetLabelAcceptanceReceipt(mutationID: snapshot.mutationID),
            sourceAcceptance
        )
        let sourceRows = try sourceSession.modelContext.fetch(
            FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()
        )
        let sourceSearchMetadata = try C45AcceptedLabelIndexRebuildBoundaryV1.metadata(
            from: sourceRows
        )
        XCTAssertEqual(sourceSearchMetadata, [try AcceptedLabelSearchMetadataV1(snapshot)])
        XCTAssertEqual(
            try LocalSearchIndexStoreV1.metadata(snapshot),
            try AcceptedLabelSearchMetadataV1(snapshot)
        )
        let searchRevisionBox = C45SearchRevisionBox(try SearchSourceRevisionV1(
            workspaceID: snapshot.workspaceID.rawValue,
            generationID: sourceSession.generationID,
            commitRevision: 1
        ))
        let searchSource = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: sourceSession.modelContext,
            workspaceID: snapshot.workspaceID.rawValue,
            generationID: sourceSession.generationID,
            revisionProvider: { searchRevisionBox.value }
        )
        let searchStore = try LocalSearchIndexStoreV1(
            applicationSupportURL: root.appendingPathComponent("search", isDirectory: true)
        )
        let searchRebuild = try SearchIndexRebuildCoordinatorV1(
            store: searchStore,
            source: searchSource,
            registry: searchSource.registry,
            makeOperationID: { id(slot + 10) }
        )
        let firstRebuild = try await searchRebuild.rebuildIfNeeded()
        XCTAssertGreaterThan(firstRebuild.indexedRecordCount, 0)
        let searchCoordinator = SearchCoordinatorV1(index: searchStore)
        let searchPlan = try searchCoordinator.makePlan(
            query: snapshot.snapshotSHA256,
            scope: .reports,
            sourceRevision: searchRevisionBox.value.commitRevision
        )
        let searchResponse = try await searchCoordinator.search(
            searchPlan,
            source: searchRevisionBox.value,
            registry: searchSource.registry
        )
        XCTAssertEqual(
            searchResponse.results.map(\.stableID),
            [WorkspaceEntityIdentityV1(
                kind: .acceptedLabelGenerationSnapshot,
                id: snapshot.snapshotID
            ).stableKey]
        )
        let searchProjection = try await searchStore.projection(
            for: searchRevisionBox.value,
            registry: searchSource.registry
        )
        XCTAssertFalse(searchProjection.records.contains {
            $0.normalizedTokens.contains(snapshot.plan.items[0].shortCode.randomBody.lowercased())
        })

        let exportRoot = root.appendingPathComponent("export", isDirectory: true)
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: sourceSession.modelContext,
            generationRootURL: sourceSession.generationRootURL,
            now: { date(Double(slot + 7)) }
        )
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: exportRoot)

        for (index, mode) in [BackupRestoreMode.clone, .fork].enumerated() {
            let support = root.appendingPathComponent("restore-\(index)", isDirectory: true)
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            let currentSession = try StoreGenerationFactory(
                applicationSupportURL: support
            ).openOrBootstrapCurrent()
            let validated = try BackupImportService(
                generationRootURL: currentSession.generationRootURL,
                makeUUID: { id(slot + 20 + index) },
                scopedAccess: .alreadyAuthorized
            ).stageAndValidate(selectedPackageURL: package)
            XCTAssertEqual(
                try validated.records.validateC45AcceptedLabelSnapshots(),
                [snapshot]
            )
            let restored = try await BackupRestoreService(
                applicationSupportURL: support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: currentSession.modelContext,
                currentGenerationID: currentSession.generationID,
                currentGenerationRootURL: currentSession.generationRootURL,
                mode: mode
            )
            let rows = try restored.modelContext.fetch(
                FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()
            )
            let rebound = try XCTUnwrap(rows.first).value()
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rebound.workspaceID, restored.workspaceID)
            XCTAssertNotEqual(rebound.workspaceID, snapshot.workspaceID)
            XCTAssertEqual(rebound.disposition, .historicCloneOrFork)
            XCTAssertEqual(rebound.snapshotID, snapshot.snapshotID)
            XCTAssertEqual(rebound.plan, snapshot.plan)
            XCTAssertEqual(rebound.manifest, snapshot.manifest)
            XCTAssertEqual(rebound.outputReceipt, snapshot.outputReceipt)
            XCTAssertEqual(rebound.plan.items.map(\.shortCode), snapshot.plan.items.map(\.shortCode))
            XCTAssertEqual(rebound.manifest.entries, snapshot.manifest.entries)
            XCTAssertEqual(
                try rebound.reprintEligibility(in: AssetLabelReprintContextV1(
                    templateRelease: try rebound.plan.template.reference,
                    rendererRelease: rebound.plan.template.rendererRelease,
                    nativeTextEnvironment: rebound.outputReceipt.nativeTextEnvironment,
                    currentBindings: []
                )),
                .historicExportOnly
            )
            let restoredJournal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID,
                allowStateBootstrap: false
            )
            try restoredJournal.validateAll()
            XCTAssertNil(
                try restoredJournal.assetLabelAcceptanceReceipt(mutationID: rebound.mutationID),
                "Clone/fork history is immutable historic provenance, never active reprint/idempotency authority"
            )
            XCTAssertEqual(
                try C45AcceptedLabelIndexRebuildBoundaryV1.metadata(from: rows),
                [try AcceptedLabelSearchMetadataV1(rebound)]
            )
        }

        let sourceQuery = AcceptedLabelGenerationSnapshotQueryV1(
            modelContext: sourceSession.modelContext
        )
        let deletedAssetID = try XCTUnwrap(snapshot.plan.items.first?.assetID)
        XCTAssertEqual(
            try contentStore.readAssetLabelArtifacts(jobID: publishedJob.id),
            publishedReadback
        )
        let unrelatedFixture = try fixture(
            itemCount: 1,
            workspaceID: workspace(slot + 100)
        )
        let unrelatedProjection = try DeterministicPDFRendererV1.renderAssetLabels(
            unrelatedFixture.plan
        )
        let unrelatedJob = try await contentLifecycle.enqueueValidatedPlan(
            unrelatedFixture.plan,
            generationEpoch: contentEpoch,
            createdAt: date(Double(slot + 101))
        )
        await contentRunner.waitUntilIdle()
        let unrelatedCompleted = try await contentRunner.job(id: unrelatedJob.id)
        XCTAssertEqual(unrelatedCompleted?.state, .succeeded)
        let unrelatedReadback = try XCTUnwrap(
            try contentStore.readAssetLabelArtifacts(jobID: unrelatedJob.id)
        )
        XCTAssertEqual(unrelatedReadback.plan, unrelatedFixture.plan)
        XCTAssertEqual(unrelatedReadback.projection, unrelatedProjection)
        let renderScratchRoot = sourceSession.generationRootURL
            .appendingPathComponent("jobs", isDirectory: true)
            .appendingPathComponent("asset-label-render", isDirectory: true)
        let matchingScratch = renderScratchRoot.appendingPathComponent(
            publishedJob.id.rawValue.uuidString.lowercased(),
            isDirectory: true
        )
        let unrelatedScratch = renderScratchRoot.appendingPathComponent(
            unrelatedJob.id.rawValue.uuidString.lowercased(),
            isDirectory: true
        )
        try await contentOperations.stage(publishedJob.id, fixture.plan, projection)
        try await contentOperations.stage(
            unrelatedJob.id,
            unrelatedFixture.plan,
            unrelatedProjection
        )
        let stagedMatchingPlan = try await contentOperations.load(
            publishedJob.id,
            fixture.plan.planSHA256
        )?.0
        let stagedUnrelatedPlan = try await contentOperations.load(
            unrelatedJob.id,
            unrelatedFixture.plan.planSHA256
        )?.0
        XCTAssertEqual(stagedMatchingPlan, fixture.plan)
        XCTAssertEqual(stagedUnrelatedPlan, unrelatedFixture.plan)
        XCTAssertTrue(fileManager.fileExists(atPath: matchingScratch.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedScratch.path))

        let deletionService = WholeSignDeletionService(
            modelContext: sourceSession.modelContext,
            generationRootURL: sourceSession.generationRootURL
        )
        let deletion = try await deletionService.delete(assetID: deletedAssetID)
        XCTAssertEqual(deletion.assetID, deletedAssetID)
        XCTAssertNil(try contentStore.readAssetLabelArtifacts(jobID: publishedJob.id))
        XCTAssertEqual(
            try contentStore.readAssetLabelArtifacts(jobID: unrelatedJob.id),
            unrelatedReadback
        )
        XCTAssertFalse(fileManager.fileExists(atPath: matchingScratch.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedScratch.path))
        XCTAssertEqual(
            try AssetLabelCanonicalCodecV1.decode(
                AssetLabelGenerationPlanV1.self,
                from: Data(contentsOf: unrelatedScratch.appendingPathComponent("plan.json"))
            ),
            unrelatedFixture.plan
        )
        let deletedSnapshot = try await sourceQuery.acceptedLabelSnapshot(
            workspaceID: snapshot.workspaceID,
            snapshotID: snapshot.snapshotID
        )
        XCTAssertNil(deletedSnapshot)
        XCTAssertNil(try journal.assetLabelAcceptanceReceipt(
            mutationID: snapshot.mutationID
        ))
        XCTAssertTrue(
            try DeletionLedgerStore(context: sourceSession.modelContext)
                .snapshot().entries.contains {
                    $0.identity.kind == .acceptedLabelGenerationSnapshot
                        && $0.identity.id == snapshot.snapshotID
                }
        )
        let remainingAssetIDs = Set(
            try sourceSession.modelContext.fetch(FetchDescriptor<Asset>()).map(\.id)
        )
        XCTAssertEqual(
            remainingAssetIDs,
            Set(snapshot.plan.items.dropFirst().map(\.assetID))
        )
        let locatorQuery = AssetLocatorRowQueryV1(
            modelContext: sourceSession.modelContext
        )
        for locator in fixture.locators.dropFirst() {
            let survivingLocator = try await locatorQuery.locator(
                id: locator.locatorID,
                workspaceID: locator.workspaceID
            )
            XCTAssertEqual(survivingLocator, locator)
        }
        _ = try await deletionService.reconcile()
        XCTAssertNil(try contentStore.readAssetLabelArtifacts(jobID: publishedJob.id))
        XCTAssertEqual(
            try contentStore.readAssetLabelArtifacts(jobID: unrelatedJob.id),
            unrelatedReadback
        )
        XCTAssertFalse(fileManager.fileExists(atPath: matchingScratch.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedScratch.path))
        searchRevisionBox.value = try SearchSourceRevisionV1(
            workspaceID: snapshot.workspaceID.rawValue,
            generationID: sourceSession.generationID,
            commitRevision: 2
        )
        _ = try await searchRebuild.rebuildIfNeeded()
        let deletedSearchPlan = try searchCoordinator.makePlan(
            query: snapshot.snapshotSHA256,
            scope: .reports,
            sourceRevision: searchRevisionBox.value.commitRevision
        )
        let deletedSearchResponse = try await searchCoordinator.search(
            deletedSearchPlan,
            source: searchRevisionBox.value,
            registry: searchSource.registry
        )
        XCTAssertTrue(deletedSearchResponse.results.isEmpty)
    }

    @MainActor
    static func verifyRealErase(slot: Int) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C45-R01-Erase-\(slot)-\(UUID().uuidString)",
            isDirectory: true
        )
        let support = root.appendingPathComponent("support", isDirectory: true)
        let caches = root.appendingPathComponent("caches", isDirectory: true)
        let temporary = root.appendingPathComponent("temporary", isDirectory: true)
        try [support, caches, temporary].forEach {
            try fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        defer { try? fileManager.removeItem(at: root) }
        let session = try StoreGenerationFactory(
            applicationSupportURL: support
        ).openOrBootstrapCurrent()
        let fixture = try fixture(itemCount: 1, workspaceID: session.workspaceID)
        let projection = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let output = try output(plan: fixture.plan, result: projection, slot: slot + 1)
        let snapshot = try snapshot(
            fixture: fixture,
            result: projection,
            output: output,
            slot: slot + 2
        )
        session.modelContext.insert(try AcceptedLabelGenerationSnapshotRow(snapshot))
        try session.modelContext.save()
        let scratch = session.generationRootURL
            .appendingPathComponent("jobs/asset-label-render/c45-erase-canary", isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        try Data("leased-label-scratch".utf8).write(
            to: scratch.appendingPathComponent("plan.json"),
            options: .atomic
        )
        let coordinator = StoreSessionCoordinator(session: session)
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        await diagnostics.prepare()
        let suite = "C45-R01-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = EraseAllService(
            applicationSupportURL: support,
            cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary,
            userDefaults: defaults,
            bundleIdentifier: suite
        )
        let erased = try await service.erase(
            confirmation: EraseAllService.requiredConfirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnostics
        ) { replacement in
            coordinator.activate(session: replacement)
        }
        try service.validateAcceptedLabelEraseClosure(session: erased.session)
        XCTAssertFalse(fileManager.fileExists(atPath: scratch.path))
        let erasedQuery = AcceptedLabelGenerationSnapshotQueryV1(
            modelContext: erased.session.modelContext
        )
        let erasedSnapshot = try await erasedQuery.acceptedLabelSnapshot(
            workspaceID: snapshot.workspaceID,
            snapshotID: snapshot.snapshotID
        )
        XCTAssertNil(erasedSnapshot)
    }

    static func expectedRevision(workspaceID: WorkspaceID, snapshotID: UUID, slot: Int) throws -> WorkspaceExpectedRevisionV1 {
        try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: id(slot),
            writerInstanceID: id(slot + 1),
            workspaceRevision: 0,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: WorkspaceEntityIdentityV1(kind: .acceptedLabelGenerationSnapshot, id: snapshotID),
                    revision: 0
                )
            ]
        )
    }

    static func actor(workspaceID: WorkspaceID, slot: Int) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(slot),
            workspaceID: workspaceID,
            displayName: "C45 local operator"
        )
        return try ActorSnapshotV1(
            snapshotID: id(slot + 1),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: .approvedBy,
            displayNameAtTime: reference.displayName,
            capturedAt: date(Double(slot))
        )
    }

    static func body(_ index: Int) -> String {
        let alphabet = Array(ManualShortCodeV1.alphabet)
        var value = index
        var digits = Array(repeating: alphabet[0], count: ManualShortCodeV1.randomBodyLength)
        for position in digits.indices.reversed() {
            digits[position] = alphabet[value % alphabet.count]
            value /= alphabet.count
        }
        return String(digits)
    }

    static func workspace(_ slot: Int) -> WorkspaceID { WorkspaceID(rawValue: id(slot)) }
    static func mutation(_ slot: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(slot)) }
    static func id(_ slot: Int) -> UUID {
        let high = UInt64(slot) >> 32
        let low = UInt64(slot) & 0xffff_ffff
        return UUID(uuidString: String(format: "%08llx-0000-0000-0000-%012llx", high, low))!
    }
    static func digest(_ character: Character) -> String { String(repeating: character, count: 64) }
    static func date(_ offset: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + offset) }
}

private struct C45ApplicationClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct C45ApplicationIDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct C45ApplicationFileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "c45/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private final class C45DeterministicShortCodeEntropy:
    ManualShortCodeCryptographicEntropyV1, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data]
    private var storedRequestCount = 0

    init(values: [Data]) { self.values = values }

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storedRequestCount
    }

    func randomBytes(count: Int) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        storedRequestCount += 1
        guard !values.isEmpty else {
            throw AssetLabelContractFailureV1.insufficientCryptographicEntropy
        }
        let value = values.removeFirst()
        guard value.count == count else {
            throw AssetLabelContractFailureV1.insufficientCryptographicEntropy
        }
        return value
    }
}

private struct C45LocatorQuery: AssetLocatorQueryingV1 {
    let locator: AssetLocatorV1
    func locator(id: UUID, workspaceID: WorkspaceID) async throws -> AssetLocatorV1? {
        locator.locatorID == id && locator.workspaceID == workspaceID ? locator : nil
    }
    func locators(lookupKey: String, workspaceID: WorkspaceID) async throws -> [AssetLocatorV1] {
        locator.lookupKey == lookupKey && locator.workspaceID == workspaceID ? [locator] : []
    }
}

private struct C45RejectingSignatureVerifier: LocalLocatorSignatureVerifyingV1 {
    func verify(payload: Data, signature: Data, key: LocatorSigningKeyReferenceV1) throws -> Bool { false }
}

private final class C45PublicationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var interrupted = false
    private var storedEffectCount = 0
    private var storedOutputSHA256 = ""
    private var storedWorkspaceRemovalCount = 0
    private var storedEraseCount = 0

    init(url: URL) { self.url = url }

    var effectCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storedEffectCount
    }

    var outputSHA256: String {
        lock.lock(); defer { lock.unlock() }
        return storedOutputSHA256
    }

    var workspaceRemovalCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storedWorkspaceRemovalCount
    }

    var eraseCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storedEraseCount
    }

    func publishThenInterruptOnce(
        jobID: LocalJobIDV1,
        outputSHA256: String
    ) throws -> LocalJobPublicationOutcomeV1 {
        lock.lock(); defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data(outputSHA256.utf8).write(to: url, options: .atomic)
            storedEffectCount += 1
            storedOutputSHA256 = outputSHA256
        }
        guard interrupted else {
            interrupted = true
            throw AssetLabelLifecycleFailureV1.publicationMismatch
        }
        return .completed(receipt(jobID: jobID, outputSHA256: outputSHA256, disposition: .adopted))
    }

    func adopt(
        jobID: LocalJobIDV1,
        outputSHA256: String
    ) throws -> LocalJobPublicationOutcomeV1 {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path),
              try String(contentsOf: url, encoding: .utf8) == outputSHA256 else {
            return .absent
        }
        storedOutputSHA256 = outputSHA256
        return .completed(receipt(jobID: jobID, outputSHA256: outputSHA256, disposition: .adopted))
    }

    func remove(workspaceID: WorkspaceID) {
        lock.lock(); defer { lock.unlock() }
        _ = workspaceID
        try? FileManager.default.removeItem(at: url)
        storedWorkspaceRemovalCount += 1
    }

    func eraseAll() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
        storedEraseCount += 1
    }

    private func receipt(
        jobID: LocalJobIDV1,
        outputSHA256: String,
        disposition: LocalJobPublicationDispositionV1
    ) -> LocalJobPublicationReceiptV1 {
        LocalJobPublicationReceiptV1(
            jobID: jobID,
            attemptCount: 1,
            kind: .render,
            outputSHA256: outputSHA256,
            disposition: disposition,
            readBackAt: Date(timeIntervalSince1970: 1_700_100_000)
        )
    }
}

@MainActor private final class C45SearchRevisionBox {
    var value: SearchSourceRevisionV1
    init(_ value: SearchSourceRevisionV1) { self.value = value }
}

private struct C45IndependentQRDecoder: AssetLabelQRIndependentDecodingV1 {
    func decode(monochromeBytes: Data, moduleCount: Int) throws -> Data {
        guard moduleCount > DeterministicPDFRendererV1.assetLabelQuietZoneModules * 2,
              monochromeBytes.count == moduleCount * moduleCount,
              monochromeBytes.allSatisfy({ $0 == 0 || $0 == 255 }),
              let provider = CGDataProvider(data: monochromeBytes as CFData),
              let image = CGImage(
                width: moduleCount,
                height: moduleCount,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: moduleCount,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: CIContext(options: [.cacheIntermediates: false]),
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
              ) else {
            throw AssetLabelRenderFailureV1.invalidQRCode
        }
        let input = CIImage(cgImage: image).transformed(
            by: CGAffineTransform(scaleX: 8, y: 8)
        )
        guard let feature = detector.features(in: input).compactMap({ $0 as? CIQRCodeFeature }).first,
              let message = feature.messageString,
              let bytes = message.data(using: .ascii) else {
            throw AssetLabelRenderFailureV1.invalidQRCode
        }
        return bytes
    }
}

@MainActor private final class C45PlanAuthority: AssetLabelAuthoritativePlanValidatingV1 {
    func validateCurrent(_ plan: AssetLabelGenerationPlanV1) async throws { try plan.validate() }
}

@MainActor private final class C45ProjectionRenderer: AssetLabelProjectionRenderingV1 {
    var failNext = false
    var completed: [String] = []
    func project(_ plan: AssetLabelGenerationPlanV1) async throws -> LabelProjectionResultV1 {
        if failNext { failNext = false; throw AssetLabelRenderFailureV1.projectionMismatch }
        let result = try DeterministicPDFRendererV1.renderAssetLabels(plan)
        completed.append(plan.planSHA256)
        return result
    }
}

@MainActor private final class C45FailClosedWriter: AssetLabelCanonicalWorkspaceWritingV1 {
    var failNext = false
    var commitCount = 0
    var recoveredSnapshot: AcceptedLabelGenerationSnapshotV1?
    func acceptedReceipt(for mutation: AssetLabelMutationV1) async throws -> AssetLabelAcceptanceReceiptV1? { nil }
    func commitAssetLabel(_ mutation: AssetLabelMutationV1) async throws -> AssetLabelAcceptanceReceiptV1 {
        commitCount += 1
        if failNext { failNext = false; throw AssetLabelContractFailureV1.scratchRequired }
        throw AssetLabelContractFailureV1.invalidReceipt
    }
}

@MainActor private final class C45AcceptingWriter: AssetLabelCanonicalWorkspaceWritingV1 {
    private var receipts: [MutationIDV1: AssetLabelAcceptanceReceiptV1] = [:]
    private(set) var commitCount = 0
    private(set) var lastSnapshot: AcceptedLabelGenerationSnapshotV1?

    func acceptedReceipt(
        for mutation: AssetLabelMutationV1
    ) async throws -> AssetLabelAcceptanceReceiptV1? {
        receipts[mutation.mutationID]
    }

    func commitAssetLabel(
        _ mutation: AssetLabelMutationV1
    ) async throws -> AssetLabelAcceptanceReceiptV1 {
        try mutation.validate()
        if let existing = receipts[mutation.mutationID] { return existing }
        let receipt = try AssetLabelAcceptanceReceiptV1(
            mutation: mutation,
            canonicalMutationReceipt: C45AssetLabelTestSupport.canonicalReceipt(
                snapshot: mutation.snapshot
            )
        )
        receipts[mutation.mutationID] = receipt
        lastSnapshot = mutation.snapshot
        commitCount += 1
        return receipt
    }
}

@MainActor private final class C45AcceptedSnapshotQuery: AcceptedLabelGenerationSnapshotQueryingV1 {
    var snapshots: [UUID: AcceptedLabelGenerationSnapshotV1] = [:]
    var byMutation: [MutationIDV1: AcceptedLabelGenerationSnapshotV1] = [:]
    func acceptedLabelSnapshot(workspaceID: WorkspaceID, mutationID: MutationIDV1) async throws -> AcceptedLabelGenerationSnapshotV1? {
        byMutation[mutationID].flatMap { $0.workspaceID == workspaceID ? $0 : nil }
    }
    func acceptedLabelSnapshot(workspaceID: WorkspaceID, snapshotID: UUID) async throws -> AcceptedLabelGenerationSnapshotV1? {
        snapshots[snapshotID].flatMap { $0.workspaceID == workspaceID ? $0 : nil }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected async expression to throw", file: file, line: line)
    } catch {}
}
private final class C46V952LabelCompatibilityTests: XCTestCase {
    func testC46AssetLabelCannotEncodeOperationalContact() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "asset-label",
            kind: .email,
            handoff: .email,
            slot: 46052
        )
    }
}
