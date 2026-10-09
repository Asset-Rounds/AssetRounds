import CoreImage
import CoreText
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

        let assetCanary = "C45_ASSET_CANARY"
        let locationCanary = "C45_LOCATION_CANARY"
        let assetOnly = try C45AssetLabelTestSupport.fixture(
            itemCount: 1,
            disclosure: .assetAndShortCode,
            assetDisplay: assetCanary,
            templateProfile: .a4SeventyByThirtySeven
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
            locationDisplay: locationCanary,
            templateProfile: .a4SeventyByThirtySeven
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

        let rtlAsset = String(repeating: "משאבה صناعية ארוכה ", count: 5)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let rtlLocation = (
            String(repeating: "gypqj ", count: 4)
                + String(repeating: "חדר שירות موقع شرقي ", count: 3)
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        let bottomInkColumns = Array(rasterRows[rtlText.pixelHeight - 1]).enumerated()
            .filter { $0.element < 255 }.map { $0.offset }
        let rowInkCounts = rasterRows.map { $0.filter { $0 < 255 }.count }
        let diagnosticFont = CTFontCreateWithName(
            DeterministicPDFRendererV1.assetLabelNativeFontPostScriptName as CFString, 7, nil)
        let lineMetrics = try rtlText.isolatedLines.enumerated().map { index, value in
            let range = CFRange(location: 0, length: (value as NSString).length)
            let selected = CTFontCreateForString(diagnosticFont, value as CFString, range)
            let attributed = NSAttributedString(string: value, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): selected,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let baseline = try DeterministicPDFRendererV1.assetLabelTextBaseline(
                ascent: ascent, descent: descent,
                lineBoxBottom: CGFloat(rtlText.pixelHeight - (index + 1) * 10))
            let glyphBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            let imageBounds = CTLineGetImageBounds(line, nil)
            return "index=\(index) width=\(width) ascent=\(ascent) descent=\(descent) baseline=\(baseline) glyphBounds=\(glyphBounds) imageBounds=\(imageBounds)"
        }
        XCTAssertTrue(rasterRows[rtlText.pixelHeight - 1].allSatisfy { $0 == 255 },
            "C45_RTL_RASTER_V1 bottomColumns=\(bottomInkColumns) rowInk=\(rowInkCounts) metrics=\(lineMetrics)")
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

    func testC45V2GlyphInsetReleaseRejectsMixedTuplesAndPlanEnvironment() async throws {
        let fixture = try C45AssetLabelTestSupport.fixture(
            itemCount: 1,
            disclosure: .assetLocationAndShortCode,
            assetDisplay: "משאבה صناعية ארוכה",
            locationDisplay: "gypqj חדר שירות موقع شرقي",
            templateProfile: .a4SeventyByThirtySeven
        )
        let currentRelease = try AssetLabelRendererReleaseReferenceV1.current
        let legacyRelease = try AssetLabelRendererReleaseReferenceV1.legacy
        XCTAssertEqual(fixture.plan.template.revision, 2)
        XCTAssertEqual(fixture.plan.template.rendererRelease, currentRelease)
        XCTAssertNotEqual(currentRelease, legacyRelease)
        let oldDigest = KernelCanonicalHashV1.sha256(Data(
            "assetrounds.deterministic-pdf-renderer-v1|deterministic-pdf-renderer-v1|asset-label-contract-v1|CORETEXT_NFC_NATIVE_POSTSCRIPT_FSI_PDI_GRAY1X_AA_OFF_LINE10_V1".utf8
        ))
        XCTAssertEqual(legacyRelease.rendererSHA256, oldDigest)
        XCTAssertThrowsError(try AssetLabelRendererReleaseReferenceV1(
            rendererID: currentRelease.rendererID,
            rendererVersion: currentRelease.rendererVersion,
            rendererSHA256: legacyRelease.rendererSHA256,
            nativeTextLayoutReleaseID: currentRelease.nativeTextLayoutReleaseID
        ))
        XCTAssertThrowsError(try AssetLabelRendererReleaseReferenceV1(
            rendererID: legacyRelease.rendererID,
            rendererVersion: legacyRelease.rendererVersion,
            rendererSHA256: legacyRelease.rendererSHA256,
            nativeTextLayoutReleaseID: currentRelease.nativeTextLayoutReleaseID
        ))

        let legacyTemplate = try AssetLabelTemplateCatalogV1.makeLegacyRelease(
            .a4SeventyByThirtySeven
        )
        XCTAssertEqual(legacyTemplate.revision, 1)
        XCTAssertNil(legacyTemplate.supersedes)
        XCTAssertEqual(fixture.plan.template.supersedes, try legacyTemplate.reference)
        XCTAssertEqual(
            try AssetLabelCanonicalCodecV1.decode(
                AssetLabelTemplateReleaseV1.self,
                from: AssetLabelCanonicalCodecV1.encode(legacyTemplate)
            ), legacyTemplate
        )
        let legacyPlan = try AssetLabelGenerationPlanV1(
            planID: fixture.plan.planID,
            workspaceID: fixture.plan.workspaceID,
            template: legacyTemplate,
            disclosure: fixture.plan.disclosure,
            items: fixture.plan.items,
            startOffset: fixture.plan.startOffset,
            localeIdentifier: fixture.plan.localeIdentifier,
            frozenGeneratedAt: fixture.plan.frozenGeneratedAt
        )
        let legacyProjection = try DeterministicPDFRendererV1.renderAssetLabels(legacyPlan)
        let currentProjection = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        XCTAssertEqual(
            legacyProjection,
            try DeterministicPDFRendererV1.renderAssetLabels(legacyPlan)
        )
        XCTAssertEqual(legacyProjection.nativeTextEnvironment.nativeTextLayoutReleaseID,
                       legacyRelease.nativeTextLayoutReleaseID)
        XCTAssertEqual(currentProjection.nativeTextEnvironment.nativeTextLayoutReleaseID,
                       currentRelease.nativeTextLayoutReleaseID)
        let currentText = try DeterministicPDFRendererV1.renderAssetLabelText(
            fixture.plan.items[0], pixelWidth: 158, pixelHeight: 30
        )
        let legacyText = try DeterministicPDFRendererV1.renderAssetLabelText(
            fixture.plan.items[0], pixelWidth: 158, pixelHeight: 30,
            rendererRelease: legacyRelease
        )
        XCTAssertEqual(currentText, try DeterministicPDFRendererV1.renderAssetLabelText(
            fixture.plan.items[0], pixelWidth: 158, pixelHeight: 30
        ))
        XCTAssertEqual(legacyText, try DeterministicPDFRendererV1.renderAssetLabelText(
            fixture.plan.items[0], pixelWidth: 158, pixelHeight: 30,
            rendererRelease: legacyRelease
        ))
        XCTAssertTrue(currentText.grayscaleBytes[0..<currentText.pixelWidth].allSatisfy { $0 == 255 })
        XCTAssertTrue(currentText.grayscaleBytes.suffix(currentText.pixelWidth).allSatisfy { $0 == 255 })
        for row in [0, 9, 10, 19, 20, 29] {
            let start = row * currentText.pixelWidth
            XCTAssertTrue(currentText.grayscaleBytes[start..<(start + currentText.pixelWidth)]
                .allSatisfy { $0 == 255 }, "V2 painted line-box border row \(row)")
        }

        func environment(_ source: AssetLabelNativeTextEnvironmentV1,
                         planSHA256: String, layoutID: String) throws -> AssetLabelNativeTextEnvironmentV1 {
            try AssetLabelNativeTextEnvironmentV1(
                planSHA256: planSHA256,
                nativeTextLayoutReleaseID: layoutID,
                coreTextVersion: source.coreTextVersion,
                operatingSystemBuild: source.operatingSystemBuild,
                baseFont: source.baseFont,
                selectedFonts: source.selectedFonts
            )
        }
        XCTAssertThrowsError(try LabelProjectionResultV1(
            plan: legacyPlan,
            artifacts: legacyProjection.artifacts,
            nativeTextEnvironment: environment(
                legacyProjection.nativeTextEnvironment,
                planSHA256: legacyPlan.planSHA256,
                layoutID: currentRelease.nativeTextLayoutReleaseID
            )
        ))
        XCTAssertThrowsError(try LabelProjectionResultV1(
            plan: fixture.plan,
            artifacts: currentProjection.artifacts,
            nativeTextEnvironment: environment(
                currentProjection.nativeTextEnvironment,
                planSHA256: fixture.plan.planSHA256,
                layoutID: legacyRelease.nativeTextLayoutReleaseID
            )
        ))
        let currentAuthority = AssetLabelAuthoritativePlanAdapterV1 { _ in
            XCTFail("A legacy plan must not reach live current-plan validation")
        }
        do {
            try await currentAuthority.validateCurrent(legacyPlan)
            XCTFail("Legacy V1 must not be a new publication authority")
        } catch {
            XCTAssertEqual(error as? AssetLabelContractFailureV1, .unsupportedTemplate)
        }
    }

    func testC45V2BaselineCandidatesRejectImpossibleHeightAndPreservePathlessNominal() throws {
        let nominal: CGFloat = 22
        let ordinaryBounds = CGRect(x: 4, y: nominal - 1, width: 10, height: 6)
        let candidates = try DeterministicPDFRendererV1.assetLabelV2CandidateBaselines(
            imageBounds: ordinaryBounds, nominalBaseline: nominal, lineBoxBottom: 20
        )
        XCTAssertEqual(candidates.first, 23)
        XCTAssertEqual(candidates, try DeterministicPDFRendererV1.assetLabelV2CandidateBaselines(
            imageBounds: ordinaryBounds, nominalBaseline: nominal, lineBoxBottom: 20
        ))
        XCTAssertLessThanOrEqual(candidates.count, 16)
        XCTAssertTrue(candidates.allSatisfy { $0 > 22 && $0 < 24 })
        XCTAssertEqual(try DeterministicPDFRendererV1.assetLabelV2CandidateBaselines(
            imageBounds: .null, nominalBaseline: nominal, lineBoxBottom: 20
        ), [nominal])
        XCTAssertThrowsError(try DeterministicPDFRendererV1.assetLabelV2CandidateBaselines(
            imageBounds: CGRect(x: 4, y: nominal - 1, width: 10, height: 9),
            nominalBaseline: nominal, lineBoxBottom: 20
        ))
        var mask = [UInt8](repeating: 255, count: 24 * 20)
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelV2MaskHasConfinedInk(
            mask, pixelWidth: 24, pixelHeight: 20, lineIndex: 0
        ), "A pathless or all-white trial cannot publish a blank required line")
        mask[3 * 24 + 4] = 0
        XCTAssertTrue(DeterministicPDFRendererV1.assetLabelV2MaskHasConfinedInk(
            mask, pixelWidth: 24, pixelHeight: 20, lineIndex: 0
        ))
        mask[0] = 0
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelV2MaskHasConfinedInk(
            mask, pixelWidth: 24, pixelHeight: 20, lineIndex: 0
        ))
        mask[0] = 255
        mask[10 * 24 + 4] = 0
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelV2MaskHasConfinedInk(
            mask, pixelWidth: 24, pixelHeight: 20, lineIndex: 0
        ))
        mask[10 * 24 + 4] = 255
        mask[3 * 24] = 0
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelV2MaskHasConfinedInk(
            mask, pixelWidth: 24, pixelHeight: 20, lineIndex: 0
        ))
    }

    func testC45LegacyV1AcceptedSnapshotKeepsExactHistoricReprintTruth() throws {
        let fixture = try C45AssetLabelTestSupport.fixture(itemCount: 1)
        let plan = try AssetLabelGenerationPlanV1(
            planID: fixture.plan.planID,
            workspaceID: fixture.plan.workspaceID,
            template: AssetLabelTemplateCatalogV1.makeLegacyRelease(.letterOneByTwoAndFiveEighths),
            disclosure: fixture.plan.disclosure,
            items: fixture.plan.items,
            startOffset: fixture.plan.startOffset,
            localeIdentifier: fixture.plan.localeIdentifier,
            frozenGeneratedAt: fixture.plan.frozenGeneratedAt
        )
        let legacyFixture = C45AssetLabelTestSupport.Fixture(
            plan: plan, locators: fixture.locators, receipts: fixture.receipts
        )
        let result = try DeterministicPDFRendererV1.renderAssetLabels(plan)
        let output = try C45AssetLabelTestSupport.output(plan: plan, result: result, slot: 9_520)
        let snapshot = try C45AssetLabelTestSupport.snapshot(
            fixture: legacyFixture, result: result, output: output, slot: 9_530
        )
        let row = try AcceptedLabelGenerationSnapshotRow(snapshot)
        XCTAssertEqual(try row.value(), snapshot)
        XCTAssertEqual(row.canonicalData, try AssetLabelCanonicalCodecV1.encode(snapshot))
        XCTAssertEqual(snapshot.plan.template.rendererRelease,
                       try AssetLabelRendererReleaseReferenceV1.legacy)
        let active = try C45AssetLabelTestSupport.currentBinding(item: plan.items[0])
        XCTAssertEqual(try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
            templateRelease: plan.template.reference,
            rendererRelease: plan.template.rendererRelease,
            nativeTextEnvironment: output.nativeTextEnvironment,
            currentBindings: [active]
        )), .activeExactReprint)
        let destination = C45AssetLabelTestSupport.workspace(9_540)
        let historic = try snapshot.rebound(
            to: destination,
            expectedRevision: C45AssetLabelTestSupport.expectedRevision(
                workspaceID: destination, snapshotID: snapshot.snapshotID, slot: 9_541
            ),
            mutationID: C45AssetLabelTestSupport.mutation(9_542),
            recordedBy: C45AssetLabelTestSupport.actor(workspaceID: destination, slot: 9_543),
            recordedAt: C45AssetLabelTestSupport.date(9_544)
        )
        XCTAssertEqual(historic.plan, plan)
        XCTAssertEqual(historic.outputReceipt, output)
        XCTAssertEqual(try historic.reprintEligibility(in: AssetLabelReprintContextV1(
            templateRelease: plan.template.reference,
            rendererRelease: plan.template.rendererRelease,
            nativeTextEnvironment: output.nativeTextEnvironment,
            currentBindings: []
        )), .historicExportOnly)
        XCTAssertEqual(try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
            templateRelease: nil,
            rendererRelease: nil,
            nativeTextEnvironment: nil,
            currentBindings: [active]
        )), .blockedMissingRelease)
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

    @MainActor
    func testEvidenceBundleExactPublicationRemovalPreservesSiblingJobs() async throws {
        try await C45AssetLabelTestSupport.verifyEvidenceBundlePublicationRecovery(slot: 940)
    }

    @MainActor
    func testV23P03C45T01FractionalReadbackRoundtripsPublishedAndAdoptedSnapshots()
        async throws {
        try await C45AssetLabelTestSupport.verifyFractionalPublicationRoundtrip(
            slot: 1_220, interruptAfterPublish: false
        )
        try await C45AssetLabelTestSupport.verifyFractionalPublicationRoundtrip(
            slot: 1_320, interruptAfterPublish: true
        )
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
    // Keep genuine control owners and their roots alive until host termination;
    // a finished job proves its reader release, not whole-registry FD closure.
    @MainActor private static var retainedJobRegistries: [GenerationLeaseRegistryV1] = []
    @MainActor private static var retainedEraseServices: [EraseAllService] = []

    @MainActor
    private static func retainJobRegistry(_ registry: GenerationLeaseRegistryV1, root: URL) {
        retainedJobRegistries.append(registry)
        FileHandle.standardError.write(Data((
            "C45_JOB_ROOT_RETAINED_V1 root=\(root.path) retention=until-host-termination\n"
        ).utf8))
    }
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
        let bindingMutationID = try mutation(30_000 + index)
        let locator = try AssetLocatorV1(
            locatorID: id(20_000 + index),
            workspaceID: workspaceID,
            assetID: assetID,
            representation: .externalKey(shortCode.externalKey()),
            state: .active,
            revision: 1,
            mutationID: bindingMutationID,
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
            mutationID: bindingMutationID,
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
        return try LabelOutputReceiptV1(
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
        let conflictingOutput = try Self.output(
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
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let registry = try factory.makeGenerationLeaseRegistry()
        retainJobRegistry(registry, root: root)
        let session = try factory.openOrBootstrapCurrent()
        let fixture = try fixture(itemCount: 2, workspaceID: session.workspaceID)
        let siteID = id(slot + 1)
        XCTAssertEqual(fixture.plan.items[0].shortCode.randomBody, "2222222222")
        let historicCodesAndStates: [(ManualShortCodeV1, AssetLocatorStateV1)] = try [
            (ManualShortCodeV1(randomBody: "3333333333"), .retired),
            (ManualShortCodeV1(randomBody: "4444444444"), .revoked),
            (ManualShortCodeV1(randomBody: "5555555555"), .replaced),
        ]
        let issuanceActor = try actor(
            workspaceID: session.workspaceID,
            slot: slot + 8
        )

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
                clock: C45ApplicationClock(value: date(Double(slot + 100))),
                idSource: C45ApplicationIDSource(value: writerInstanceID),
                fileAuthority: C45ApplicationFileAuthority(),
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
                journalStore: journal
            )
        }
        let query = AssetLocatorRowQueryV1(modelContext: session.modelContext)
        var seededIssuances: [ManualShortCodeIssuanceReceiptV1] = []
        var historicLocators: [AssetLocatorV1] = []
        var historicReceipts: [LocatorBindingReceiptV1] = []
        var replacementLocator: AssetLocatorV1?
        do {
            let seedWriter = try makeWriter()
            for (index, item) in fixture.plan.items.enumerated() {
                let firstSignMutationID = try mutation(slot + 500 + index)
                let firstSign = FirstSignMutationV1(
                    siteID: siteID,
                    newSite: index == 0 ? .init(
                        id: siteID,
                        label: "C45 issuer site",
                        address: nil,
                        timeZoneID: nil
                    ) : nil,
                    assetID: item.assetID,
                    assetLabel: "C45 issuer asset",
                    packID: SignPack.illuminatedSignV1.packID,
                    packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                    packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                    createdAt: date(Double(slot + 1 + index)),
                    initialPlacementMutationID: firstSignMutationID,
                    initialPlacementEventID: id(slot + 600 + index),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                        rawValue: id(slot + 700 + index)
                    )
                )
                _ = try seedWriter.execute(
                    .createFirstSign(firstSign),
                    mutationID: firstSignMutationID
                )
                XCTAssertNotNil(try journal.receipt(mutationID: firstSignMutationID))
            }
            let actorMutationID = try mutation(slot + 502)
            _ = try seedWriter.execute(
                .applyPartyAccountability(.appendActorSnapshot(issuanceActor)),
                mutationID: actorMutationID
            )
            XCTAssertNotNil(try journal.receipt(mutationID: actorMutationID))
            for index in 0..<4 {
                let seedOperation = try ManualShortCodeIssuanceOperationV1(
                    workspaceID: session.workspaceID,
                    assetID: fixture.plan.items[0].assetID,
                    locatorID: id(slot + 200 + index),
                    bindingReceiptID: id(slot + 210 + index),
                    mutationID: mutation(slot + 220 + index),
                    recordedBy: issuanceActor,
                    requestedAt: date(Double(slot + 8))
                )
                let seedEntropy = C45DeterministicShortCodeEntropy(values: [
                    Data(
                        repeating: UInt8(index),
                        count: ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt
                    ),
                ])
                let coordinator = ManualShortCodeIssuanceCoordinatorV1(
                    query: query,
                    writer: seedWriter,
                    entropy: seedEntropy
                )
                let seeded = try await coordinator.issue(seedOperation)
                try seeded.validate()
                XCTAssertEqual(seedEntropy.requestCount, 1)
                XCTAssertEqual(
                    seeded.request.shortCode.randomBody,
                    String(repeating: String(index + 2), count: 10)
                )
                XCTAssertNotNil(try journal.receipt(mutationID: seedOperation.mutationID))
                seededIssuances.append(seeded)
            }
            for (index, pair) in historicCodesAndStates.enumerated() {
                let predecessor = seededIssuances[index + 1]
                XCTAssertEqual(predecessor.request.shortCode, pair.0)
                let lifecycleMutationID = try mutation(slot + 230 + index)
                let replacement: AssetLocatorV1? = pair.1 == .replaced
                    ? try AssetLocatorV1(
                        locatorID: id(slot + 240),
                        workspaceID: session.workspaceID,
                        assetID: fixture.plan.items[0].assetID,
                        representation: .externalKey(try ExternalKeyV1(
                            namespaceID: "asset",
                            normalization: .asciiCaseInsensitive,
                            suppliedValue: "C45-I01-Replacement-\(slot)"
                        )),
                        state: .active,
                        revision: 1,
                        mutationID: lifecycleMutationID,
                        recordedAt: date(Double(slot + 8))
                    )
                    : nil
                let successor = try AssetLocatorV1(
                    locatorID: predecessor.locator.locatorID,
                    workspaceID: session.workspaceID,
                    assetID: predecessor.locator.assetID,
                    representation: predecessor.locator.representation,
                    state: pair.1,
                    replacedByLocatorID: replacement?.locatorID,
                    predecessorLocatorSHA256: predecessor.locator.locatorSHA256,
                    revision: 2,
                    mutationID: lifecycleMutationID,
                    recordedAt: date(Double(slot + 8))
                )
                let action: LocatorBindingActionV1
                switch pair.1 {
                case .retired: action = .retire
                case .revoked: action = .revoke
                case .replaced: action = .replace
                case .active: XCTFail("Historic reuse fixture must not be active"); continue
                }
                let preview = try LocatorBindingPreviewV1(
                    workspaceID: session.workspaceID,
                    action: action,
                    before: predecessor.locator.reference,
                    after: successor.reference,
                    replacement: replacement?.reference,
                    generatedAt: date(Double(slot + 8))
                )
                let lifecycleReceipt = try LocatorBindingReceiptV1(
                    receiptID: id(slot + 250 + index),
                    preview: preview,
                    recordedBy: issuanceActor,
                    predecessor: predecessor.bindingReceipt,
                    revision: 2,
                    mutationID: lifecycleMutationID,
                    recordedAt: date(Double(slot + 8))
                )
                let payload: AssetLocatorMutationPayloadV1
                if let replacement {
                    payload = .replace(
                        successor,
                        replacement: replacement,
                        receipt: lifecycleReceipt,
                        predecessorLocator: predecessor.locator,
                        predecessorReceipt: predecessor.bindingReceipt
                    )
                } else {
                    payload = .transition(
                        successor,
                        receipt: lifecycleReceipt,
                        predecessorLocator: predecessor.locator,
                        predecessorReceipt: predecessor.bindingReceipt
                    )
                }
                let lifecycleMutation = try AssetLocatorMutationV1(
                    workspaceID: session.workspaceID,
                    mutationID: lifecycleMutationID,
                    payload: payload
                )
                _ = try seedWriter.commitAssetLocator(lifecycleMutation)
                XCTAssertNotNil(try journal.receipt(mutationID: lifecycleMutationID))
                let persistedSuccessor = try await query.locator(
                    id: successor.locatorID,
                    workspaceID: session.workspaceID
                )
                XCTAssertEqual(
                    persistedSuccessor,
                    successor
                )
                XCTAssertEqual(lifecycleReceipt.predecessorReceiptID, predecessor.bindingReceipt.receiptID)
                XCTAssertEqual(lifecycleReceipt.predecessorReceiptSHA256, predecessor.bindingReceipt.receiptSHA256)
                historicLocators.append(successor)
                historicReceipts.append(lifecycleReceipt)
                replacementLocator = replacement ?? replacementLocator
            }
        }
        // The seed writer's external alias ends before independent recovery writers start.
        let collidingLocator = seededIssuances[0].locator
        XCTAssertEqual(
            collidingLocator.representation,
            .externalKey(try fixture.plan.items[0].shortCode.externalKey())
        )
        let persistedReplacement = try XCTUnwrap(replacementLocator)
        let readReplacement = try await query.locator(
            id: persistedReplacement.locatorID,
            workspaceID: session.workspaceID
        )
        XCTAssertEqual(
            readReplacement,
            persistedReplacement
        )
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
        XCTAssertFalse(try availabilityWriter.manualShortCodeIsAvailable(
            fixture.plan.items[0].shortCode,
            workspaceID: session.workspaceID
        ))
        for pair in historicCodesAndStates {
            XCTAssertFalse(try availabilityWriter.manualShortCodeIsAvailable(
                pair.0,
                workspaceID: session.workspaceID
            ))
        }
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
            6
        )
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>()).count,
            8
        )
        // Four genuine binds, three historic successors, and the final bind
        // leave six current locators (including the replacement) and eight receipts.
        let persistedLocatorHeads = try session.modelContext.fetch(
            FetchDescriptor<AssetLocatorRow>()
        ).map { try $0.value() }
        XCTAssertEqual(
            Set(persistedLocatorHeads.map(\.locatorID)),
            Set([collidingLocator.locatorID, persistedReplacement.locatorID, issued.locator.locatorID]
                + historicLocators.map(\.locatorID))
        )
        let persistedReceiptValues = try session.modelContext.fetch(
            FetchDescriptor<LocatorBindingReceiptRow>()
        ).map { try $0.value() }
        XCTAssertEqual(
            Set(persistedReceiptValues.map(\.receiptID)),
            Set(seededIssuances.map { $0.bindingReceipt.receiptID }
                + historicReceipts.map(\.receiptID) + [issued.bindingReceipt.receiptID])
        )
        _ = try AssetLocatorLifecycleClosureV1(
            locators: seededIssuances.map(\.locator) + historicLocators
                + [persistedReplacement, issued.locator],
            receipts: seededIssuances.map(\.bindingReceipt) + historicReceipts
                + [issued.bindingReceipt]
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
        // Physical exclusion binds the actual installed-layout directory. The
        // synthetic logical epoch below remains this fixture's independent law.
        let generationRoot = root.appendingPathComponent("FieldEvidenceData/generations", isDirectory: true)
            .appendingPathComponent(id(slot + 1).uuidString.lowercased(), isDirectory: true)
        let ledgerRoot = root.appendingPathComponent("ledger", isDirectory: true)
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        try fileManager.createDirectory(at: generationRoot, withIntermediateDirectories: true)

        let jobRegistry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        retainJobRegistry(jobRegistry, root: root)
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
        let fixture = try Self.fixture(itemCount: 2, workspaceID: workspace(slot + 2))
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
            generationLeaseRegistry: jobRegistry,
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
            generationLeaseRegistry: jobRegistry,
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

        // A distinct real publication under the same workspace marker parent.
        let sibling = try Self.fixture(itemCount: 1, workspaceID: fixture.plan.workspaceID)
        let siblingProjection = try DeterministicPDFRendererV1.renderAssetLabels(sibling.plan)
        let siblingJob = try await recoveredLifecycle.enqueueValidatedPlan(
            sibling.plan, generationEpoch: epoch, createdAt: date(Double(slot + 19))
        )
        await recoveredRunner.waitUntilIdle()
        let completedSiblingJob = try await recoveredRunner.job(id: siblingJob.id)
        XCTAssertEqual(completedSiblingJob?.state, .succeeded)
        XCTAssertNotEqual(siblingJob.id, job.id)
        let siblingReadback = try XCTUnwrap(try contentStore.readAssetLabelArtifacts(jobID: siblingJob.id))
        XCTAssertEqual(siblingReadback.plan, sibling.plan)
        XCTAssertEqual(siblingReadback.projection, siblingProjection)

        let unrelated = try Self.fixture(itemCount: 1, workspaceID: workspace(slot + 20))
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
        let targetMarker = generationRoot.appendingPathComponent(
            "content/\(fixture.plan.workspaceID.rawValue.uuidString.lowercased())/.asset-label-publications/\(job.id.rawValue.uuidString.lowercased())/publication.json"
        )
        XCTAssertTrue(fileManager.fileExists(atPath: targetMarker.path))
        try contentStore.removeAssetLabelPublishedOutput(binding)
        XCTAssertNil(try contentStore.readAssetLabelArtifacts(jobID: job.id))
        XCTAssertFalse(fileManager.fileExists(atPath: targetMarker.path))
        for artifact in readback.publishedArtifacts {
            let targetBytes = generationRoot.appendingPathComponent(
                "content/\(artifact.reference.workspaceID)/\(artifact.reference.contentID)/original.bin"
            )
            XCTAssertFalse(fileManager.fileExists(atPath: targetBytes.path))
        }
        try contentStore.removeAssetLabelPublishedOutput(binding)
        // Readback verifies surviving markers and every immutable artifact's bytes/digest.
        XCTAssertEqual(try contentStore.readAssetLabelArtifacts(jobID: siblingJob.id), siblingReadback)
        XCTAssertEqual(
            try contentStore.readAssetLabelArtifacts(jobID: unrelatedJob.id),
            unrelatedReadback
        )

        let cancelledFixture = try Self.fixture(
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
            generationLeaseRegistry: jobRegistry,
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
            generationLeaseRegistry: jobRegistry,
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
        let ledgerRoot = root.appendingPathComponent("ledger", isDirectory: true)
        let stagingRoot = root.appendingPathComponent("runner-staging", isDirectory: true)
        let publishedURL = root.appendingPathComponent("published-manifest.sha256")
        let jobRegistry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        retainJobRegistry(jobRegistry, root: root)
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
            generationLeaseRegistry: jobRegistry,
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
            generationLeaseRegistry: jobRegistry,
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
    static func verifyFractionalPublicationRoundtrip(
        slot: Int,
        interruptAfterPublish: Bool
    ) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C45-fractional-readback-\(slot)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        // The registry acquires a descriptor on this exact owned support root.
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let registry = try factory.makeGenerationLeaseRegistry()
        retainJobRegistry(registry, root: root)
        let session = try factory.openOrBootstrapCurrent()
        let epoch = try factory.currentGenerationEpoch()
        let fixture = try fixture(itemCount: 1, workspaceID: session.workspaceID)
        let projection = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let stagingRoot = session.generationRootURL.appendingPathComponent(
            "jobs", isDirectory: true
        )
        let ledgerRoot = root.appendingPathComponent("ledger", isDirectory: true)
        let contentStore = EvidenceBundleStore(generationRootURL: session.generationRootURL)
        // The original R01 failure captured this genuine fractional readback
        // bit pattern; C45's millisecond codec decoded it one ULP higher.
        let fractionalReadback = Date(
            timeIntervalSinceReferenceDate: Double(bitPattern: 0x41c834a70c4e9e23)
        )
        XCTAssertNotEqual(
            try AssetLabelCanonicalCodecV1.decode(
                Date.self,
                from: AssetLabelCanonicalCodecV1.encode(fractionalReadback)
            ),
            fractionalReadback,
            "The injected sub-millisecond readback must exercise the canonicalization defect"
        )
        let production = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: stagingRoot,
            contentStore: contentStore,
            readBackClock: { fractionalReadback }
        )
        let operations: AssetLabelArtifactOperationsV1
        if interruptAfterPublish {
            // The real content-store effect occurs; only the attempt to
            // persist its first receipt is interrupted. Cancellation then
            // makes the runner use production's exact adopt-only readback.
            operations = try AssetLabelArtifactOperationsV1.durableStaging(
                jobStagingRootURL: stagingRoot,
                publishOrAdopt: { job, planSHA256, outputSHA256 in
                    _ = try production.publishOrAdopt(job, planSHA256, outputSHA256)
                    throw AssetLabelLifecycleFailureV1.publicationMismatch
                },
                adoptOnly: production.adoptOnly,
                publishedReadback: production.publishedReadback,
                removePublishedOutput: production.removePublishedOutput,
                removePublishedWorkspace: production.removePublishedWorkspace,
                eraseAllPublished: production.eraseAllPublished,
                discardUncommitted: production.discardUncommitted
            )
        } else {
            operations = production
        }
        let publicationAdapter = GenerationLocalJobPublicationAdapterV1(
            currentGenerationEpoch: { epoch },
            withAuthorizedCommit: { expected, effect in
                guard expected == epoch else {
                    throw GenerationLocalJobPublicationFailureV1.staleGeneration
                }
                return try effect()
            }
        )
        let runner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: ledgerRoot),
            stagingRootURL: stagingRoot,
            generationLeaseRegistry: registry,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let acceptingWriter = C45AcceptingWriter()
        let lifecycle = await AssetLabelLifecycleAdapterV1(
            authority: AssetLabelAuthoritativePlanAdapterV1 { try $0.validate() },
            writer: acceptingWriter,
            query: C45AcceptedSnapshotQuery(),
            jobs: runner,
            artifacts: operations
        )
        let job = try await lifecycle.enqueueValidatedPlan(
            fixture.plan,
            generationEpoch: epoch,
            createdAt: date(Double(slot))
        )
        await runner.waitUntilIdle()
        if interruptAfterPublish {
            let pendingValue = try await runner.job(id: job.id)
            let pending = try XCTUnwrap(pendingValue)
            XCTAssertEqual(pending.state, .awaitingPublication)
            XCTAssertNil(pending.publicationReceipt)
            XCTAssertNotNil(try contentStore.readAssetLabelArtifacts(jobID: job.id))
            _ = try await runner.requestCancellation(id: job.id)
            await runner.waitUntilIdle()
        }
        let completedValue = try await runner.job(id: job.id)
        let completed = try XCTUnwrap(completedValue)
        XCTAssertEqual(completed.state, .succeeded)
        let receipt = try XCTUnwrap(completed.publicationReceipt)
        XCTAssertEqual(receipt.disposition, interruptAfterPublish ? .adopted : .published)
        XCTAssertGreaterThanOrEqual(receipt.readBackAt, fractionalReadback)
        XCTAssertLessThan(
            receipt.readBackAt.timeIntervalSince1970
                - fractionalReadback.timeIntervalSince1970,
            0.002
        )
        XCTAssertEqual(
            try AssetLabelCanonicalCodecV1.decode(
                Date.self,
                from: AssetLabelCanonicalCodecV1.encode(receipt.readBackAt)
            ),
            receipt.readBackAt
        )
        let reopenedStore = try LocalJobStoreV1(applicationSupportURL: ledgerRoot)
        let reopenedValue = try await reopenedStore.job(id: job.id)
        let reopened = try XCTUnwrap(reopenedValue)
        XCTAssertEqual(reopened.publicationReceipt, receipt)
        let acceptance = try await lifecycle.acceptPublishedJob(
            jobID: job.id,
            outputReceiptID: id(slot + 19),
            snapshotID: id(slot + 20),
            expectedRevision: try expectedRevision(
                workspaceID: fixture.plan.workspaceID,
                snapshotID: id(slot + 20),
                slot: slot + 21
            ),
            mutationID: mutation(slot + 22),
            recordedBy: actor(workspaceID: fixture.plan.workspaceID, slot: slot + 23),
            recordedAt: date(Double(slot + 24))
        )
        let snapshot = try XCTUnwrap(acceptingWriter.lastSnapshot)
        try acceptance.validate(snapshot: snapshot)
        XCTAssertEqual(snapshot.outputReceipt.publicationBinding.publicationReceipt, receipt)
        XCTAssertEqual(snapshot.outputReceipt.generatedAt, receipt.readBackAt)
        let row = try AcceptedLabelGenerationSnapshotRow(snapshot)
        session.modelContext.insert(row)
        try session.modelContext.save()
        let rows = try session.modelContext.fetch(
            FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try XCTUnwrap(rows.first).value(), snapshot)
        XCTAssertEqual(row.canonicalData, try AssetLabelCanonicalCodecV1.encode(snapshot))
        XCTAssertEqual(
            try AssetLabelCanonicalCodecV1.decode(
                AcceptedLabelGenerationSnapshotV1.self,
                from: row.canonicalData
            ),
            snapshot
        )
    }

    @MainActor
    static func verifyRealBackupRestoreCloneAndFork(slot: Int) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C45-R01-\(slot)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceSupport = root.appendingPathComponent("source-support", isDirectory: true)
        try fileManager.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let sourceFactory = StoreGenerationFactory(applicationSupportURL: sourceSupport)
        let contentRegistry = try sourceFactory.makeGenerationLeaseRegistry()
        retainJobRegistry(contentRegistry, root: root)
        let sourceSession = try sourceFactory.openOrBootstrapCurrent()
        let contractFixture = try fixture(itemCount: 3, workspaceID: sourceSession.workspaceID)
        let writerInstanceID = id(slot + 3)
        let journal = try MutationJournalStoreV1(
            modelContext: sourceSession.modelContext,
            identity: sourceSession.workspaceIdentity,
            generationID: sourceSession.generationID
        )
        let sourceWriter = try WorkspaceWriterV1(
            identity: sourceSession.workspaceIdentity,
            generationID: sourceSession.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerInstanceID),
            clock: C45ApplicationClock(value: date(Double(slot + 100))),
            idSource: C45ApplicationIDSource(value: writerInstanceID),
            fileAuthority: C45ApplicationFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: sourceSession.modelContext),
            journalStore: journal
        )
        let siteID = id(slot + 8)
        for (index, item) in contractFixture.plan.items.enumerated() {
            let firstSignMutationID = try mutation(slot + 200 + index)
            let firstSign = FirstSignMutationV1(
                siteID: siteID,
                newSite: index == 0 ? .init(
                    id: siteID,
                    label: "C45 source site",
                    address: nil,
                    timeZoneID: nil
                ) : nil,
                assetID: item.assetID,
                assetLabel: "C45 asset",
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                createdAt: date(Double(slot + index)),
                initialPlacementMutationID: firstSignMutationID,
                initialPlacementEventID: id(slot + 300 + index),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                    rawValue: id(slot + 400 + index)
                )
            )
            _ = try sourceWriter.execute(
                .createFirstSign(firstSign),
                mutationID: firstSignMutationID
            )
            XCTAssertNotNil(try journal.receipt(mutationID: firstSignMutationID))
        }
        let sourceActor = try actor(
            workspaceID: sourceSession.workspaceID,
            slot: slot + 5
        )
        let actorMutationID = try mutation(slot + 210)
        _ = try sourceWriter.execute(
            .applyPartyAccountability(.appendActorSnapshot(sourceActor)),
            mutationID: actorMutationID
        )
        XCTAssertNotNil(try journal.receipt(mutationID: actorMutationID))
        let sourceLocatorQuery = AssetLocatorRowQueryV1(modelContext: sourceSession.modelContext)
        var issuedBindings: [ManualShortCodeIssuanceReceiptV1] = []
        let alphabet = Array(ManualShortCodeV1.alphabet)
        for (index, item) in contractFixture.plan.items.enumerated() {
            let codeBytes = try item.shortCode.randomBody.map { character -> UInt8 in
                UInt8(try XCTUnwrap(alphabet.firstIndex(of: character)))
            }
            let entropy = C45DeterministicShortCodeEntropy(values: [
                Data(codeBytes + Array(
                    repeating: UInt8(0),
                    count: ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt
                        - codeBytes.count
                ))
            ])
            let operation = try ManualShortCodeIssuanceOperationV1(
                workspaceID: sourceSession.workspaceID,
                assetID: item.assetID,
                locatorID: contractFixture.locators[index].locatorID,
                bindingReceiptID: contractFixture.receipts[index].receiptID,
                mutationID: contractFixture.locators[index].mutationID,
                recordedBy: sourceActor,
                requestedAt: date(Double(slot + 5))
            )
            let coordinator = ManualShortCodeIssuanceCoordinatorV1(
                query: sourceLocatorQuery,
                writer: sourceWriter,
                entropy: entropy
            )
            let issued = try await coordinator.issue(operation)
            try issued.validate()
            XCTAssertEqual(issued.request.shortCode, item.shortCode)
            XCTAssertEqual(entropy.requestCount, 1)
            XCTAssertNotNil(try journal.receipt(mutationID: operation.mutationID))
            let persistedLocator = try await sourceLocatorQuery.locator(
                id: operation.locatorID,
                workspaceID: sourceSession.workspaceID
            )
            let persistedBinding = try await sourceLocatorQuery.bindingReceipt(
                id: operation.bindingReceiptID,
                workspaceID: sourceSession.workspaceID
            )
            XCTAssertEqual(persistedLocator, issued.locator)
            XCTAssertEqual(persistedBinding, issued.bindingReceipt)
            issuedBindings.append(issued)
        }
        let assetRevisions = Dictionary(uniqueKeysWithValues:
            try sourceWriter.currentRevision().entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let boundItems = try zip(contractFixture.plan.items, issuedBindings).map {
            (original, issued) -> AssetLabelItemSnapshotV1 in
            let assetIdentity = try WorkspaceEntityIdentityV1(
                kind: .asset, id: original.assetID
            )
            let assetRevision = try XCTUnwrap(assetRevisions[assetIdentity])
            XCTAssertEqual(assetRevision, 1)
            return try AssetLabelItemSnapshotV1(
                workspaceID: sourceSession.workspaceID,
                assetID: original.assetID,
                assetRevision: assetRevision,
                locator: issued.locator,
                bindingReceipt: issued.bindingReceipt,
                shortCode: original.shortCode,
                assetDisplay: original.assetDisplay,
                locationDisplay: original.locationDisplay,
                disclosure: original.disclosure,
                orderIndex: original.orderIndex
            )
        }
        let boundPlan = try AssetLabelGenerationPlanV1(
            planID: contractFixture.plan.planID,
            workspaceID: sourceSession.workspaceID,
            template: contractFixture.plan.template,
            disclosure: contractFixture.plan.disclosure,
            items: boundItems,
            startOffset: contractFixture.plan.startOffset,
            localeIdentifier: contractFixture.plan.localeIdentifier,
            frozenGeneratedAt: contractFixture.plan.frozenGeneratedAt
        )
        let fixture = Fixture(
            plan: boundPlan,
            locators: issuedBindings.map(\.locator),
            receipts: issuedBindings.map(\.bindingReceipt)
        )
        XCTAssertEqual(
            fixture.plan.items.map(\.shortCode),
            contractFixture.plan.items.map(\.shortCode)
        )
        XCTAssertEqual(
            fixture.plan.items.map(\.assetDisplay),
            contractFixture.plan.items.map(\.assetDisplay)
        )
        XCTAssertEqual(
            fixture.plan.items.map(\.locationDisplay),
            contractFixture.plan.items.map(\.locationDisplay)
        )
        let placementEvents = try sourceSession.modelContext.fetch(
            FetchDescriptor<AssetPlacementEventRow>()
        ).map { try $0.value() }
        XCTAssertEqual(
            placementEvents.count,
            3
        )
        XCTAssertEqual(
            Set(placementEvents.map(\.assetID)),
            Set(contractFixture.plan.items.map(\.assetID))
        )
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
        let contentEpoch = try sourceFactory.currentGenerationEpoch()
        XCTAssertEqual(contentEpoch.generationID, sourceSession.generationID)
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
            generationLeaseRegistry: contentRegistry,
            generationPublicationAdapter: contentPublicationAdapter,
            maximumConcurrency: 1
        )
        let sourceQuery = AcceptedLabelGenerationSnapshotQueryV1(
            modelContext: sourceSession.modelContext
        )
        let contentLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: AssetLabelAuthoritativePlanAdapterV1 { plan in
                try plan.validate()
                guard plan.workspaceID == sourceSession.workspaceID else {
                    throw WorkspaceMutationFailureV1.wrongWorkspace
                }
                for item in plan.items {
                    let assetID = item.assetID
                    let assets = try sourceSession.modelContext.fetch(
                        FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })
                    )
                    let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
                    let stableKey = identity.stableKey
                    let revisions = try sourceSession.modelContext.fetch(
                        FetchDescriptor<EntityMutationRevisionRow>(
                            predicate: #Predicate { $0.stableIdentity == stableKey }
                        )
                    )
                    let locator = try await sourceLocatorQuery.locator(
                        id: item.locator.locatorID,
                        workspaceID: plan.workspaceID
                    )
                    let receipt = try await sourceLocatorQuery.bindingReceipt(
                        id: item.bindingReceiptID,
                        workspaceID: plan.workspaceID
                    )
                    guard let locator,
                          let receipt,
                          assets.count == 1,
                          revisions.count == 1,
                          let revision = revisions.first?.revision,
                          revision > 0,
                          UInt64(revision) == item.assetRevision,
                          locator.assetID == item.assetID,
                          locator.state == item.locatorState,
                          try locator.reference == item.locator,
                          receipt.after == item.locator,
                          receipt.revision == item.bindingReceiptRevision,
                          receipt.receiptSHA256 == item.bindingReceiptSHA256 else {
                        throw WorkspaceMutationFailureV1.invalidCommand
                    }
                }
            },
            writer: sourceWriter,
            query: sourceQuery,
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
        let acceptanceMutationID = try mutation(slot + 4)
        let current = try sourceWriter.currentRevision()
        let expectedAcceptanceRevision = try WorkspaceExpectedRevisionV1(
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
        )
        let accepted = try await contentLifecycle.acceptPublishedJob(
            jobID: publishedJob.id,
            outputReceiptID: output.receiptID,
            snapshotID: snapshotID,
            expectedRevision: expectedAcceptanceRevision,
            mutationID: acceptanceMutationID,
            recordedBy: sourceActor,
            recordedAt: date(Double(slot + 6))
        )
        let persistedSnapshot = try await sourceQuery.acceptedLabelSnapshot(
            workspaceID: sourceSession.workspaceID,
            mutationID: acceptanceMutationID
        )
        let snapshot = try XCTUnwrap(persistedSnapshot)
        let mutation = try AssetLabelMutationV1(snapshot: snapshot)
        try accepted.validate(snapshot: snapshot)
        XCTAssertEqual(snapshot.outputReceipt.publicationBinding, output.publicationBinding)
        XCTAssertEqual(snapshot.outputReceipt.receiptID, output.receiptID)
        XCTAssertEqual(
            snapshot.outputReceipt.generatedAt,
            try XCTUnwrap(completedPublishedJob.publicationReceipt).readBackAt
        )
        // Diagnose the actual published receipt without changing the snapshot,
        // its canonical bytes, or the row initializer's fail-closed check.
        do {
            let canonicalProbe = try AssetLabelCanonicalCodecV1.encode(snapshot)
            let decodedProbe = try AssetLabelCanonicalCodecV1.decode(
                AcceptedLabelGenerationSnapshotV1.self,
                from: canonicalProbe
            )
            let components: [(String, Bool)] = [
                ("schemaVersion", snapshot.schemaVersion == decodedProbe.schemaVersion),
                ("snapshotID", snapshot.snapshotID == decodedProbe.snapshotID),
                ("workspaceID", snapshot.workspaceID == decodedProbe.workspaceID),
                ("plan", snapshot.plan == decodedProbe.plan),
                ("manifest", snapshot.manifest == decodedProbe.manifest),
                ("outputReceipt", snapshot.outputReceipt == decodedProbe.outputReceipt),
                ("activationDecision", snapshot.activationDecision == decodedProbe.activationDecision),
                ("disposition", snapshot.disposition == decodedProbe.disposition),
                ("expectedRevision", snapshot.expectedRevision == decodedProbe.expectedRevision),
                ("mutationID", snapshot.mutationID == decodedProbe.mutationID),
                ("recordedBy", snapshot.recordedBy == decodedProbe.recordedBy),
                ("recordedAt", snapshot.recordedAt == decodedProbe.recordedAt),
                ("revision", snapshot.revision == decodedProbe.revision),
                ("snapshotSHA256", snapshot.snapshotSHA256 == decodedProbe.snapshotSHA256)
            ]
            let mismatches = components.filter { !$0.1 }.map { $0.0 }
            let originalReadBackAt = snapshot.outputReceipt.publicationBinding
                .publicationReceipt.readBackAt
            let decodedReadBackAt = decodedProbe.outputReceipt.publicationBinding
                .publicationReceipt.readBackAt
            var diagnostic = "C45_R01_ROUNDTRIP_V1 fullEqual=\(snapshot == decodedProbe) "
                + "mismatches=\(mismatches.joined(separator: ",")) "
                + "readBackAtEqual=\(originalReadBackAt == decodedReadBackAt)"
            if originalReadBackAt != decodedReadBackAt {
                diagnostic += " readBackAtBitsOriginal=\(String(originalReadBackAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16))"
                    + " readBackAtBitsDecoded=\(String(decodedReadBackAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16))"
            }
            FileHandle.standardError.write(Data((diagnostic + "\n").utf8))
        } catch {
            FileHandle.standardError.write(Data((
                "C45_R01_ROUNDTRIP_V1 decodeErrorType=\(String(reflecting: type(of: error)))\n"
            ).utf8))
        }
        try journal.validateAll()
        let sourceAcceptance = try XCTUnwrap(
            journal.assetLabelAcceptanceReceipt(mutationID: snapshot.mutationID)
        )
        try sourceAcceptance.validate(snapshot: snapshot)
        XCTAssertEqual(sourceAcceptance, accepted)
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
            try C45AcceptedLabelIndexStoreBoundaryV1.metadata(snapshot),
            try AcceptedLabelSearchMetadataV1(snapshot)
        )
        let searchRevisionBox = C45SearchRevisionBox(try SearchSourceRevisionV1(
            workspaceID: snapshot.workspaceID.rawValue,
            generationID: sourceSession.generationID,
            commitRevision: try sourceWriter.currentRevision().revision
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
            scope: SearchScopeV1.reports,
            sourceRevision: searchRevisionBox.value.commitRevision
        )
        let searchResponse = try await searchCoordinator.search(
            searchPlan,
            source: searchRevisionBox.value,
            registry: searchSource.registry
        )
        XCTAssertEqual(
            searchResponse.results.map(\.stableID),
            [try WorkspaceEntityIdentityV1(
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
            let restoreService = try BackupRestoreService(
                applicationSupportURL: support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            )
            restoreService.restorePhaseDiagnosticForTesting = { phase in
                FileHandle.standardError.write(Data("C45_R01_RESTORE_PHASE_V1 \(phase)\n".utf8))
            }
            let restored = try await restoreService.restore(
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

        let deletedAssetID = try XCTUnwrap(snapshot.plan.items.first?.assetID)
        XCTAssertEqual(
            try contentStore.readAssetLabelArtifacts(jobID: publishedJob.id),
            publishedReadback
        )
        let unrelatedBase = try Self.fixture(
            itemCount: 1,
            workspaceID: workspace(slot + 100)
        )
        let unrelatedValue = try Self.item(
            index: slot + 100,
            workspaceID: unrelatedBase.plan.workspaceID,
            templateDisclosure: unrelatedBase.plan.disclosure,
            orderIndex: 0
        )
        let unrelatedFixture = Fixture(
            plan: try AssetLabelGenerationPlanV1(
                planID: id(slot + 500),
                workspaceID: unrelatedBase.plan.workspaceID,
                template: unrelatedBase.plan.template,
                disclosure: unrelatedBase.plan.disclosure,
                items: [unrelatedValue.item],
                startOffset: unrelatedBase.plan.startOffset,
                localeIdentifier: unrelatedBase.plan.localeIdentifier,
                frozenGeneratedAt: unrelatedBase.plan.frozenGeneratedAt
            ),
            locators: [unrelatedValue.locator],
            receipts: [unrelatedValue.receipt]
        )
        XCTAssertTrue(Set(unrelatedFixture.plan.items.map(\.assetID))
            .isDisjoint(with: Set(snapshot.plan.items.map(\.assetID))))
        XCTAssertFalse(unrelatedFixture.plan.items.contains {
            $0.assetID == deletedAssetID
        })
        let unrelatedProjection = try DeterministicPDFRendererV1.renderAssetLabels(
            unrelatedFixture.plan
        )
        // This deliberately foreign workspace is rendered only to prove that
        // deleting the accepted source label leaves sibling content intact.
        // The source lifecycle's live authority must continue to reject it;
        // this fixture lifecycle has no canonical acceptance writer.
        let unrelatedWriter = C45FailClosedWriter()
        let unrelatedLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: AssetLabelAuthoritativePlanAdapterV1 { plan in
                guard plan == unrelatedFixture.plan else {
                    throw WorkspaceMutationFailureV1.wrongWorkspace
                }
            },
            writer: unrelatedWriter,
            query: C45AcceptedSnapshotQuery(),
            jobs: contentRunner,
            artifacts: contentOperations
        )
        let unrelatedJob = try await unrelatedLifecycle.enqueueValidatedPlan(
            unrelatedFixture.plan,
            generationEpoch: contentEpoch,
            createdAt: date(Double(slot + 101))
        )
        await contentRunner.waitUntilIdle()
        XCTAssertEqual(unrelatedWriter.commitCount, 0)
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
            commitRevision: searchRevisionBox.value.commitRevision + 1
        )
        _ = try await searchRebuild.rebuildIfNeeded()
        let deletedSearchPlan = try searchCoordinator.makePlan(
            query: snapshot.snapshotSHA256,
            scope: SearchScopeV1.reports,
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
        // The harness retains the actual Router, operation and physical root
        // host lifetime; no unchecked root-removal defer is permitted.
        let owner = V23EraseOperationHarnessV1(retainingRoot: root, applicationSupportURL: support,
            runtime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            profileRegistry: try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        defer { owner.router.entitlementProcessor?.stop() }
        let suite = "C45-R01-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var admittedReservation: AppAccessGateV1.EraseAdoptionToken?
        var completedReceipts: [CompletedEraseReceiptV1] = []
        weak var originalCoordinator: StoreSessionCoordinator?
        weak var originalContext: ModelContext?
        weak var originalContainer: ModelContainer?
        let prepared = try await { () async throws -> (
            seeded: (workspaceID: WorkspaceID, snapshotID: UUID, scratch: URL, generationID: UUID),
            service: EraseAllService
        ) in
            let (coordinator, diagnostics) = try await owner.startOriginalOwner()
            originalCoordinator = coordinator
            originalContext = coordinator.modelContext
            originalContainer = coordinator.modelContext.container
            let seeded = try await { () async throws -> (
                workspaceID: WorkspaceID, snapshotID: UUID, scratch: URL, generationID: UUID
            ) in
                let writer = coordinator.workspaceWriter
                let fixtureJobOwner = try coordinator.originalAssetLabelFixtureJobOwnerForTesting(
                    expectedWriter: writer
                )
                let epoch = fixtureJobOwner.epoch
                let contractFixture = try fixture(itemCount: 1, workspaceID: coordinator.workspaceID)
                let journal = try MutationJournalStoreV1(
                    modelContext: coordinator.modelContext,
                    identity: coordinator.workspaceIdentity,
                    generationID: coordinator.generationID
                )
                let firstSignMutationID = try mutation(slot + 200)
                let assetID = try XCTUnwrap(contractFixture.plan.items.first?.assetID)
                _ = try writer.execute(.createFirstSign(FirstSignMutationV1(
                    siteID: id(slot + 8),
                    newSite: .init(
                        id: id(slot + 8),
                        label: "C45 Erase source site",
                        address: nil,
                        timeZoneID: nil
                    ),
                    assetID: assetID,
                    assetLabel: "C45 Erase source asset",
                    packID: SignPack.illuminatedSignV1.packID,
                    packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                    packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                    createdAt: date(Double(slot)),
                    initialPlacementMutationID: firstSignMutationID,
                    initialPlacementEventID: id(slot + 300),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                        rawValue: id(slot + 400)
                    )
                )), mutationID: firstSignMutationID)
                XCTAssertNotNil(try journal.receipt(mutationID: firstSignMutationID))
                let recordedBy = try actor(workspaceID: coordinator.workspaceID, slot: slot + 5)
                let actorMutationID = try mutation(slot + 210)
                _ = try writer.execute(
                    .applyPartyAccountability(.appendActorSnapshot(recordedBy)),
                    mutationID: actorMutationID
                )
                XCTAssertNotNil(try journal.receipt(mutationID: actorMutationID))
                let locatorQuery = AssetLocatorRowQueryV1(modelContext: coordinator.modelContext)
                let firstItem = try XCTUnwrap(contractFixture.plan.items.first)
                let alphabet = Array(ManualShortCodeV1.alphabet)
                let codeBytes = try firstItem.shortCode.randomBody.map { character -> UInt8 in
                    UInt8(try XCTUnwrap(alphabet.firstIndex(of: character)))
                }
                let entropy = C45DeterministicShortCodeEntropy(values: [
                    Data(codeBytes + Array(
                        repeating: UInt8(0),
                        count: ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt
                            - codeBytes.count
                    ))
                ])
                let issuance = try ManualShortCodeIssuanceOperationV1(
                    workspaceID: coordinator.workspaceID,
                    assetID: assetID,
                    locatorID: try XCTUnwrap(contractFixture.locators.first).locatorID,
                    bindingReceiptID: try XCTUnwrap(contractFixture.receipts.first).receiptID,
                    mutationID: try XCTUnwrap(contractFixture.locators.first).mutationID,
                    recordedBy: recordedBy,
                    requestedAt: date(Double(slot + 5))
                )
                let issued = try await ManualShortCodeIssuanceCoordinatorV1(
                    query: locatorQuery,
                    writer: writer,
                    entropy: entropy
                ).issue(issuance)
                try issued.validate()
                XCTAssertEqual(issued.request.shortCode, firstItem.shortCode)
                XCTAssertEqual(entropy.requestCount, 1)
                XCTAssertNotNil(try journal.receipt(mutationID: issuance.mutationID))
                let persistedLocator = try await locatorQuery.locator(
                    id: issuance.locatorID, workspaceID: coordinator.workspaceID
                )
                let persistedBinding = try await locatorQuery.bindingReceipt(
                    id: issuance.bindingReceiptID, workspaceID: coordinator.workspaceID
                )
                XCTAssertEqual(persistedLocator, issued.locator)
                XCTAssertEqual(persistedBinding, issued.bindingReceipt)
                let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
                let assetRevision = try XCTUnwrap(writer.currentRevision().entityRevisions.first {
                    $0.identity == assetIdentity
                }?.revision)
                XCTAssertEqual(assetRevision, 1)
                let boundItem = try AssetLabelItemSnapshotV1(
                    workspaceID: coordinator.workspaceID,
                    assetID: assetID,
                    assetRevision: assetRevision,
                    locator: issued.locator,
                    bindingReceipt: issued.bindingReceipt,
                    shortCode: firstItem.shortCode,
                    assetDisplay: firstItem.assetDisplay,
                    locationDisplay: firstItem.locationDisplay,
                    disclosure: firstItem.disclosure,
                    orderIndex: firstItem.orderIndex
                )
                let plan = try AssetLabelGenerationPlanV1(
                    planID: contractFixture.plan.planID,
                    workspaceID: coordinator.workspaceID,
                    template: contractFixture.plan.template,
                    disclosure: contractFixture.plan.disclosure,
                    items: [boundItem],
                    startOffset: contractFixture.plan.startOffset,
                    localeIdentifier: contractFixture.plan.localeIdentifier,
                    frozenGeneratedAt: contractFixture.plan.frozenGeneratedAt
                )
                let projection = try DeterministicPDFRendererV1.renderAssetLabels(plan)
                let contentStore = EvidenceBundleStore(generationRootURL: coordinator.generationRootURL)
                XCTAssertEqual(epoch.generationID, coordinator.generationID)
                // Build C05 through the source coordinator's canonical retained owner.
                // The later Erase capture borrows this same retained runner.
                let production = try ProductionCompositionRoot(
                    storeSession: coordinator,
                    diagnosticsStore: diagnostics,
                    profileRegistry: try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
                )
                let workflow = try await production.makeAssetLabelWorkflow(
                    generationEpoch: epoch,
                    accessGate: owner.accessGate
                )
                let runnerValue = try coordinator.originalC05RunnerForErase()
                let runner = try XCTUnwrap(runnerValue,
                    "Canonical C05 workflow must retain the original coordinator-owned runner")
                let query = AcceptedLabelGenerationSnapshotQueryV1(
                    modelContext: coordinator.modelContext
                )
                let lifecycle = workflow.lifecycle
                let job = try await lifecycle.enqueueValidatedPlan(
                    plan,
                    generationEpoch: epoch,
                    createdAt: date(Double(slot + 1))
                )
                await runner.waitUntilIdle()
                let completedJobValue = try await runner.job(id: job.id)
                let completedJob = try XCTUnwrap(completedJobValue)
                XCTAssertEqual(completedJob.state, .succeeded)
                let published = try XCTUnwrap(
                    try contentStore.readAssetLabelArtifacts(jobID: job.id)
                )
                XCTAssertEqual(published.plan, plan)
                XCTAssertEqual(published.projection, projection)
                let outputReceipt = try output(
                    plan: plan,
                    result: projection,
                    slot: slot + 1,
                    publishedArtifacts: published.publishedArtifacts,
                    publicationReceipt: try XCTUnwrap(completedJob.publicationReceipt)
                )
                let snapshotID = id(slot + 2)
                let acceptanceMutationID = try mutation(slot + 4)
                let current = try writer.currentRevision()
                let expected = try WorkspaceExpectedRevisionV1(
                    workspaceID: coordinator.workspaceID,
                    generationID: current.generationID,
                    writerInstanceID: current.writerInstanceID,
                    workspaceRevision: current.revision,
                    entityRevisions: [
                        WorkspaceEntityRevisionV1(
                            identity: WorkspaceEntityIdentityV1(
                                kind: .acceptedLabelGenerationSnapshot, id: snapshotID
                            ),
                            revision: 0
                        )
                    ]
                )
                let acceptance = try await lifecycle.acceptPublishedJob(
                    jobID: job.id,
                    outputReceiptID: outputReceipt.receiptID,
                    snapshotID: snapshotID,
                    expectedRevision: expected,
                    mutationID: acceptanceMutationID,
                    recordedBy: recordedBy,
                    recordedAt: date(Double(slot + 6))
                )
                let persistedSnapshot = try await query.acceptedLabelSnapshot(
                    workspaceID: coordinator.workspaceID,
                    mutationID: acceptanceMutationID
                )
                let snapshot = try XCTUnwrap(persistedSnapshot)
                try acceptance.validate(snapshot: snapshot)
                XCTAssertEqual(snapshot.plan, plan)
                XCTAssertNotNil(try journal.assetLabelAcceptanceReceipt(
                    mutationID: acceptanceMutationID
                ))
                try journal.validateAll()
                let scratch = coordinator.generationRootURL
                    .appendingPathComponent("jobs/asset-label-render/c45-erase-canary", isDirectory: true)
                try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
                try Data("leased-label-scratch".utf8).write(
                    to: scratch.appendingPathComponent("plan.json"), options: .atomic
                )
                return (snapshot.workspaceID, snapshot.snapshotID, scratch, coordinator.generationID)
            }()
            // All external job, registry, journal, writer and context aliases
            // have left their seed frame before the original owner is admitted.
            try await owner.admit(coordinator: coordinator)
            XCTAssertThrowsError(try coordinator.originalAssetLabelFixtureJobOwnerForTesting(
                expectedWriter: coordinator.workspaceWriter
            ), "The original job-owner accessor must close after real Erase admission") { error in
                XCTAssertEqual(error as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
            }
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: support,
                cachesDirectoryURL: caches,
                temporaryDirectoryURL: temporary,
                userDefaults: defaults,
                bundleIdentifier: "com.palatis3.fieldrecord",
                defaultsDomainName: suite,
                admitErase: { subject in
                    let reservation = try await owner.admitSubject(subject)
                    admittedReservation = reservation
                    return reservation
                },
                didCompleteErase: { completedReceipts.append($0) }
            ))
            // The configured service retains the actual pre-cleanup frame and
            // controls. Keep it with the root even if preparation throws.
            retainedEraseServices.append(service)
            try await owner.prepareCompatibility(service: service,
                confirmation: EraseAllService.requiredConfirmation,
                coordinator: coordinator, diagnostics: diagnostics)
            return (seeded, service)
        }()
        let seeded = prepared.seeded
        let service = prepared.service
        guard originalCoordinator == nil, originalContext == nil, originalContainer == nil else {
            XCTFail("Original asset-label Erase readers must drain before cleanup")
            throw V23EraseOperationHarnessV1.Failure.drainPending
        }
        XCTAssertTrue(completedReceipts.isEmpty)
        try await owner.completeCleanup()
        XCTAssertEqual(completedReceipts.count, 1)
        let deliveredReceipt = try XCTUnwrap(completedReceipts.first)
        let reservation = try XCTUnwrap(admittedReservation)
        XCTAssertEqual(deliveredReceipt.reservation, reservation)
        XCTAssertEqual(deliveredReceipt.subject, reservation.subject)
        try await owner.adoptCompletedReceipt()
        let token = try await owner.accessGate.beginContentRead(for: .startupRecovery)
        let erasedSession = try token.withContentRead(for: .startupRecovery) {
            try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        }
        try token.withContentRead(for: .startupRecovery) {
            try service.validateAcceptedLabelEraseClosure(session: erasedSession)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: seeded.scratch.path))
        let erasedQuery = AcceptedLabelGenerationSnapshotQueryV1(
            modelContext: erasedSession.modelContext
        )
        try await owner.accessGate.validateContentRead(token, for: .startupRecovery)
        let erasedSnapshot = try await erasedQuery.acceptedLabelSnapshot(
            workspaceID: seeded.workspaceID,
            snapshotID: seeded.snapshotID
        )
        try await owner.accessGate.validateContentRead(token, for: .startupRecovery)
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
final class C46V952LabelCompatibilityTests: XCTestCase {
    func testC46AssetLabelCannotEncodeOperationalContact() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "asset-label",
            kind: .email,
            handoff: .email,
            slot: 46052
        )
    }
}
