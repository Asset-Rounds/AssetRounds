import CryptoKit
import Foundation
import XCTest

@testable import FieldEvidenceApp

enum V907CompatibilitySupport {
    private final class BundleMarker {}

    private struct GeneratedCaseArtifactV1: Codable, Equatable {
        let artifactVersion: String
        let caseID: String
        let dependencyFamilies: [CompatibilityArtifactFamilyV1]
        let expectedDisposition: CompatibilityExpectedDispositionV1
        let family: CompatibilityArtifactFamilyV1
        let generatorSeed: UInt64
        let generatorVersion: String
        let kind: CompatibilityCaseKindV1
        let scenarioTags: [String]
        let schema: String
        let schemaVersion: Int
    }

    private struct HistoricReportOpenV1: Codable, Equatable {
        struct Display: Codable, Equatable {
            struct Section: Codable, Equatable {
                let body: String
                let heading: String
                let id: String
            }

            let sections: [Section]
            let title: String
        }

        struct Generator: Codable, Equatable {
            let name: String
            let seed: UInt64
            let version: String
        }

        let artifactDigest: String
        let containsCustomerData: Bool
        let containsSecrets: Bool
        let displaySnapshot: Display
        let fixtureID: String
        let generator: Generator
        let immutable: Bool
        let licenseIdentifier: String
        let nativeCompileRan: Bool
        let pdfFixturePath: String
        let pdfSHA256: String
        let rendererProof: Bool
        let reportSchema: String
        let reportVersion: String
        let schema: String
        let schemaVersion: Int
        let synthetic: Bool
    }

    struct CorpusFixtureMetadata: Decodable {
        let schema: String
        let schemaVersion: Int
        let artifactDigest: String
        let fixtureDigests: [String: String]
        let generatedCaseArtifacts: [String: String]
        let evidenceIDs: [String]
        let workspaceScenarioTags: [String]
        let immutable: Bool
        let synthetic: Bool
        let containsCustomerData: Bool
        let containsSecrets: Bool
    }

    struct SeedFixtureMetadata: Decodable {
        struct Generator: Decodable {
            let name: String
            let seed: UInt64
            let version: String
        }

        struct WorkspaceVariant: Decodable {
            let id: String
            let recordCount: Int
            let dstBoundary: Bool
            let unicode: Bool
            let scenarioTags: [String]
        }

        let schema: String
        let schemaVersion: Int
        let artifactDigest: String
        let generator: Generator
        let scenarioTags: [String]
        let workspaceVariants: [WorkspaceVariant]
        let immutable: Bool
        let synthetic: Bool
        let containsCustomerData: Bool
        let containsSecrets: Bool
    }

    static func fixtureData(_ name: String, extension fileExtension: String = "json") throws -> Data {
        let bundle = Bundle(for: BundleMarker.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: "Fixtures/V21/Compatibility"
            ) ?? bundle.url(forResource: name, withExtension: fileExtension),
            "Missing compatibility fixture \(name).\(fileExtension)"
        )
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func corpus() throws -> CompatibilityCorpusManifestV1 {
        try JSONDecoder().decode(
            CompatibilityCorpusManifestV1.self,
            from: fixtureData("V21P01C07CompatibilityCorpusV1")
        )
    }

    static func seed() throws -> ReleaseSeedCorpusV1 {
        try JSONDecoder().decode(
            ReleaseSeedCorpusV1.self,
            from: fixtureData("V21P01C07PreV23SeedV1")
        )
    }

    static func corpusMetadata() throws -> CorpusFixtureMetadata {
        try JSONDecoder().decode(
            CorpusFixtureMetadata.self,
            from: fixtureData("V21P01C07CompatibilityCorpusV1")
        )
    }

    static func seedMetadata() throws -> SeedFixtureMetadata {
        try JSONDecoder().decode(
            SeedFixtureMetadata.self,
            from: fixtureData("V21P01C07PreV23SeedV1")
        )
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func generatedArtifact(
        for caseID: String,
        metadata: CorpusFixtureMetadata? = nil
    ) throws -> Data {
        let resolvedMetadata: CorpusFixtureMetadata
        if let metadata {
            resolvedMetadata = metadata
        } else {
            resolvedMetadata = try corpusMetadata()
        }
        guard let encoded = resolvedMetadata.generatedCaseArtifacts[caseID],
              !encoded.isEmpty,
              let data = Data(base64Encoded: encoded, options: []),
              !data.isEmpty else {
            throw CompatibilityContractErrorV1.invalidCorpus
        }
        return data
    }

    static func generatedArtifact(
        for item: CompatibilityCaseManifestV1,
        metadata: CorpusFixtureMetadata? = nil
    ) throws -> Data {
        let data = try generatedArtifact(for: item.caseID, metadata: metadata)
        guard sha256(data) == item.artifactSHA256 else {
            throw CompatibilityContractErrorV1.invalidCorpus
        }
        return data
    }

    static func executeCase(
        for item: CompatibilityCaseManifestV1,
        metadata: CorpusFixtureMetadata? = nil
    ) throws -> String {
        let data: Data
        switch item.source {
        case .deterministicGenerator:
            data = try generatedArtifact(for: item, metadata: metadata)
            guard let generatorVersion = item.generatorVersion,
                  let generatorSeed = item.generatorSeed else {
                throw CompatibilityContractErrorV1.invalidCorpus
            }
            let descriptor: GeneratedCaseArtifactV1 = try CompatibilityCanonicalV1.decode(
                GeneratedCaseArtifactV1.self,
                from: data
            )
            guard descriptor.schema == "V23P01C07GeneratedCaseArtifactV1",
                  descriptor.schemaVersion == 1,
                  descriptor.caseID == item.caseID,
                  descriptor.family == item.family,
                  descriptor.artifactVersion == item.artifactVersion,
                  descriptor.kind == item.kind,
                  item.source == .deterministicGenerator,
                  descriptor.generatorVersion == generatorVersion,
                  descriptor.generatorSeed == generatorSeed,
                  descriptor.dependencyFamilies == item.dependencyFamilies,
                  descriptor.scenarioTags == item.scenarioTags,
                  descriptor.expectedDisposition == item.expectedDisposition else {
                throw CompatibilityContractErrorV1.invalidCorpus
            }
        case .checkedFixture:
            let url = URL(fileURLWithPath: item.artifactRelativePath)
            data = try fixtureData(
                url.deletingPathExtension().lastPathComponent,
                extension: url.pathExtension
            )
            guard sha256(data) == item.artifactSHA256,
                  item.kind == .positive else {
                throw CompatibilityContractErrorV1.invalidCorpus
            }
            switch item.family {
            case .reportOpenJSON:
                guard let object = try JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                      Set(object.keys) == [
                          "artifactDigest", "containsCustomerData", "containsSecrets",
                          "displaySnapshot", "fixtureID", "generator", "immutable",
                          "licenseIdentifier", "nativeCompileRan", "pdfFixturePath",
                          "pdfSHA256", "rendererProof", "reportSchema", "reportVersion",
                          "schema", "schemaVersion", "synthetic",
                      ],
                      let display = object["displaySnapshot"] as? [String: Any],
                      Set(display.keys) == ["sections", "title"],
                      let sections = display["sections"] as? [[String: Any]],
                      !sections.isEmpty,
                      sections.allSatisfy({ Set($0.keys) == ["body", "heading", "id"] }),
                      let generator = object["generator"] as? [String: Any],
                      Set(generator.keys) == ["name", "seed", "version"] else {
                    throw CompatibilityContractErrorV1.invalidCorpus
                }
                let report = try JSONDecoder().decode(HistoricReportOpenV1.self, from: data)
                let roundTrip = try JSONDecoder().decode(
                    HistoricReportOpenV1.self,
                    from: JSONEncoder().encode(report)
                )
                guard roundTrip == report,
                      report.schema == "V21P01C07HistoricReportOpenV1",
                      report.schemaVersion == 1,
                      report.reportSchema == "ReportSnapshotV1",
                      report.reportVersion == item.artifactVersion,
                      report.fixtureID == "V21-P01-C07-HISTORIC-REPORT-OPEN-V1",
                      report.immutable,
                      report.synthetic,
                      !report.nativeCompileRan,
                      !report.rendererProof,
                      report.licenseIdentifier == "SYNTHETIC_INTERNAL_FIXTURE_V1",
                      report.generator.name == "p01_c07_contracts.py",
                      report.generator.seed == 230_107,
                      report.generator.version == "p01-c07-seed-v1",
                      Set(report.displaySnapshot.sections.map(\.id)).count
                        == report.displaySnapshot.sections.count,
                      !report.containsCustomerData,
                      !report.containsSecrets,
                      CompatibilityCanonicalV1.validSHA256(report.artifactDigest),
                      CompatibilityCanonicalV1.validSHA256(report.pdfSHA256),
                      CompatibilityCanonicalV1.validRelativePath(report.pdfFixturePath) else {
                    throw CompatibilityContractErrorV1.invalidCorpus
                }
                let pdfURL = URL(fileURLWithPath: report.pdfFixturePath)
                let reportPDF = try fixtureData(
                    pdfURL.deletingPathExtension().lastPathComponent,
                    extension: pdfURL.pathExtension
                )
                guard sha256(reportPDF) == report.pdfSHA256 else {
                    throw CompatibilityContractErrorV1.invalidCorpus
                }
            case .reportPDF:
                let header = Data("%PDF-".utf8)
                let eofLF = Data("%%EOF\n".utf8)
                let eofCRLF = Data("%%EOF\r\n".utf8)
                let hasEOF = data.suffix(eofLF.count).elementsEqual(eofLF)
                    || data.suffix(eofCRLF.count).elementsEqual(eofCRLF)
                guard item.artifactVersion == "template1",
                      data.starts(with: header),
                      data.range(of: Data("/Type /Catalog".utf8)) != nil,
                      data.range(of: Data("startxref".utf8)) != nil,
                      hasEOF else {
                    throw CompatibilityContractErrorV1.invalidCorpus
                }
            default:
                throw CompatibilityContractErrorV1.invalidCorpus
            }
        }
        let observed = sha256(data)
        guard observed == (item.normalizedExpectedSHA256 ?? item.artifactSHA256) else {
            throw CompatibilityContractErrorV1.invalidRunReceipt
        }
        return observed
    }

    static func caseText(_ item: CompatibilityCaseManifestV1) -> String {
        ([item.caseID, item.artifactRelativePath] + item.scenarioTags)
            .joined(separator: " ")
            .lowercased()
    }

    static func containsCase(
        _ corpus: CompatibilityCorpusManifestV1,
        family: CompatibilityArtifactFamilyV1? = nil,
        tokens: [String]
    ) -> Bool {
        corpus.cases.contains { item in
            (family == nil || item.family == family)
                && tokens.allSatisfy { caseText(item).contains($0.lowercased()) }
        }
    }

    static func result(
        for item: CompatibilityCaseManifestV1,
        observedOutputSHA256: String
    ) throws -> CompatibilityCaseRunResultV1 {
        return CompatibilityCaseRunResultV1(
            caseID: item.caseID,
            caseManifestSHA256: try item.canonicalSHA256(),
            outcome: .passed,
            normalizedOutputSHA256: observedOutputSHA256,
            failureCode: nil
        )
    }

    static func result(
        for item: CompatibilityCaseManifestV1,
        outcome: CompatibilityCaseRunOutcomeV1,
        failureCode: String
    ) throws -> CompatibilityCaseRunResultV1 {
        guard outcome != .passed else {
            throw CompatibilityContractErrorV1.invalidRunReceipt
        }
        return CompatibilityCaseRunResultV1(
            caseID: item.caseID,
            caseManifestSHA256: try item.canonicalSHA256(),
            outcome: outcome,
            normalizedOutputSHA256: nil,
            failureCode: failureCode
        )
    }

    static func receipt(
        runID: String,
        corpus: CompatibilityCorpusManifestV1,
        selection: CompatibilityRunSelectionV1,
        mode: CompatibilityRunModeV1,
        affectedFamilies: [CompatibilityArtifactFamilyV1] = [],
        results: [CompatibilityCaseRunResultV1]
    ) throws -> CompatibilityRunReceiptV1 {
        CompatibilityRunReceiptV1(
            runID: runID,
            corpusSHA256: try corpus.canonicalSHA256(),
            selection: selection,
            mode: mode,
            affectedFamilies: affectedFamilies.sorted { $0.rawValue < $1.rawValue },
            selectedCaseIDs: corpus.caseIDs(
                for: selection,
                affectedFamilies: affectedFamilies
            ),
            results: results
        )
    }

    static func replacing(
        _ item: CompatibilityCaseManifestV1,
        artifactRelativePath: String? = nil,
        artifactSHA256: String? = nil,
        artifactVersion: String? = nil,
        kind: CompatibilityCaseKindV1? = nil,
        expectedDisposition: CompatibilityExpectedDispositionV1? = nil,
        containsCustomerData: Bool? = nil,
        containsSecrets: Bool? = nil,
        synthetic: Bool? = nil
    ) -> CompatibilityCaseManifestV1 {
        CompatibilityCaseManifestV1(
            schemaVersion: item.schemaVersion,
            caseID: item.caseID,
            family: item.family,
            artifactVersion: artifactVersion ?? item.artifactVersion,
            kind: kind ?? item.kind,
            artifactRelativePath: artifactRelativePath ?? item.artifactRelativePath,
            artifactSHA256: artifactSHA256 ?? item.artifactSHA256,
            normalizedExpectedSHA256: item.normalizedExpectedSHA256,
            source: item.source,
            generatorVersion: item.generatorVersion,
            generatorSeed: item.generatorSeed,
            dependencyFamilies: item.dependencyFamilies,
            scenarioTags: item.scenarioTags,
            expectedDisposition: expectedDisposition ?? item.expectedDisposition,
            synthetic: synthetic ?? item.synthetic,
            licenseIdentifier: item.licenseIdentifier,
            containsCustomerData: containsCustomerData ?? item.containsCustomerData,
            containsSecrets: containsSecrets ?? item.containsSecrets,
            immutable: item.immutable,
            representative: item.representative
        )
    }

    /// Replays the frozen report-open and PDF fixtures that C42 uses as its
    /// historic-output compatibility anchors.  Returning the observed digest
    /// by case ID lets the cross-market lane prove byte parity without copying
    /// or rewriting a released fixture.
    static func crossMarketHistoricReportDigests() throws -> [String: String] {
        let manifest = try corpus()
        let metadata = try corpusMetadata()
        let selected = manifest.cases.filter {
            $0.kind == .positive
                && ($0.family == .reportOpenJSON || $0.family == .reportPDF)
        }
        guard !selected.isEmpty,
              selected.contains(where: { $0.family == .reportOpenJSON }),
              selected.contains(where: { $0.family == .reportPDF }),
              Set(selected.map(\.caseID)).count == selected.count else {
            throw CompatibilityContractErrorV1.invalidCorpus
        }
        return try Dictionary(uniqueKeysWithValues: selected.map { item in
            (item.caseID, try executeCase(for: item, metadata: metadata))
        })
    }
}
