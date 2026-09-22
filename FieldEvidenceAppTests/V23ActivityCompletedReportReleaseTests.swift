import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23ActivityCompletedReportReleaseTests: XCTestCase {
    private typealias Release = ActivityCompletedReportReleaseV1
    private typealias Failure = ActivityCompletedReportReleaseFailureV1

    private var resources: [ActivityCompletedReportResourceV1] {
        [Release.manifestResource, Release.fileSchemaResource, Release.reportSchemaResource]
    }

    private struct ResourceBundle {
        let bundle: Bundle
        let root: URL
        let files: [String: URL]
    }

    private func actualResourceURL(_ name: String) throws -> URL {
        let root = try XCTUnwrap(Release.appBundle.resourceURL)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: nil, options: []))
        var matches: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == name {
            matches.append(url)
        }
        XCTAssertEqual(matches.count, 1, name)
        return try XCTUnwrap(matches.first)
    }

    /// Copy actual app-bundled release bytes; every subject calls loadBundled.
    /// The helper supplies only a filesystem location, never alternate pins.
    private func resourceBundle(flattened: Bool = true) throws -> ResourceBundle {
        _ = try Release.loadBundled()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("completed-release-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let info: [String: String] = ["CFBundleIdentifier": "tests.completed-release.\(UUID().uuidString)",
                                    "CFBundleName": "CompletedReleaseTests", "CFBundlePackageType": "BNDL"]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: root.appendingPathComponent("Info.plist"))
        var files: [String: URL] = [:]
        for resource in resources {
            var destination = root
            if !flattened {
                destination = destination.appendingPathComponent("Resources/Contracts", isDirectory: true)
                if resource.fileName.hasSuffix(".schema.json") {
                    destination = destination.appendingPathComponent("OpenJSON", isDirectory: true)
                }
            }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            destination = destination.appendingPathComponent(resource.fileName)
            try FileManager.default.copyItem(at: actualResourceURL(resource.fileName), to: destination)
            files[resource.fileName] = destination
        }
        return ResourceBundle(bundle: try XCTUnwrap(Bundle(url: root)), root: root, files: files)
    }

    private func assertFailure(_ expected: Failure, bundle: Bundle,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Release.loadBundled(bundle: bundle), file: file, line: line) { error in
            XCTAssertEqual(error as? Failure, expected, file: file, line: line)
        }
    }

    private func legacyBytes() throws -> Data {
        let bundle = Bundle(for: Self.self)
        let name = "V23P03C06LegacyContractManifestV1"
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json",
                                          subdirectory: "Fixtures/V23/Activities")
            ?? bundle.url(forResource: name, withExtension: "json"))
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes.count, 96_442)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(bytes),
                       "b142747430f74fc3b2d0b403f9e60bcf08d3ba49f5e1249a2790d95eb0a3643c")
        return bytes
    }

    private func variant(_ source: ContractManifestV1, identity: String? = nil, version: Int? = nil,
                         compatibility: ContractCompatibilityRuleV1? = nil,
                         objects: [ContractObjectDefinitionV1]? = nil,
                         registry: ReportSectionRegistryV1? = nil) throws -> ContractManifestV1 {
        try ContractManifestV1(manifestID: identity ?? source.manifestID,
            manifestVersion: version ?? source.manifestVersion, codec: source.codec,
            compatibility: compatibility ?? source.compatibility, objects: objects ?? source.objects,
            enums: source.enums, reportSectionRegistry: registry ?? source.reportSectionRegistry,
            schemaVersion: source.schemaVersion)
    }

    func testActualAppBundleAdmitsExactCompleteManifestAndBothSchemas() throws {
        let release = try Release.loadBundled()
        let manifest = release.manifest
        // BEGIN GENERATED COMPLETED RELEASE EXPECTATIONS
        XCTAssertEqual(manifest.manifestID, "activity-completed-contract-manifest-v1")
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.codec.codecVersion, 2)
        XCTAssertEqual(manifest.objects.count, 249)
        XCTAssertEqual(manifest.enums.count, 139)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.sha256(manifest),
                       "7ed5d023b813d3c4363e346e393bb0aec2d9ef87b78a9aef8a79405d5ae1b2ac")
        // END GENERATED COMPLETED RELEASE EXPECTATIONS
        XCTAssertEqual(try release.admitFrozenManifest(manifest), manifest)
        let frozenBytes = try WorkspaceMutationCanonicalV1.data(manifest)
        let readback = try JSONDecoder().decode(ContractManifestV1.self, from: frozenBytes)
        XCTAssertEqual(try release.admitFrozenManifest(readback), manifest)
        let schemas = [release.fileSchema, release.reportSchema]
        XCTAssertEqual(schemas.map(\.rootTypeID), ["activity-completed-file-v1", "activity-completed-report-v1"])
        for schema in schemas {
            try schema.projection.validate()
            XCTAssertEqual(schema.projection.manifestSHA256, Release.manifestResource.canonicalSHA256)
            XCTAssertEqual(schema.projection.schemaSHA256, schema.resource.canonicalSHA256)
            XCTAssertFalse(schema.projection.networkFetchRequired)
            XCTAssertEqual(schema.projection.schemaID,
                "https://schemas.assetrounds.local/v23/p03/c06/\(schema.rootTypeID)/schema")
        }
        for resource in resources {
            let bytes = try Data(contentsOf: actualResourceURL(resource.fileName))
            XCTAssertEqual(bytes.count, resource.byteCount)
            XCTAssertEqual(KernelCanonicalHashV1.sha256(bytes), resource.rawSHA256)
            XCTAssertEqual(KernelCanonicalHashV1.sha256(Data(bytes.dropLast())), resource.canonicalSHA256)
        }
    }

    func testPublishedDefinitionsAndSevenSectionRegistryRemainExactButOldReleaseIsExcluded() throws {
        let release = try Release.loadBundled()
        let originalBytes = try legacyBytes()
        let legacy = try JSONDecoder().decode(ContractManifestV1.self, from: originalBytes)
        XCTAssertEqual(legacy.objects.count, 29)
        XCTAssertEqual(legacy.enums.count, 15)
        XCTAssertEqual(legacy.reportSectionRegistry.sections.count, 7)
        XCTAssertEqual(release.manifest.reportSectionRegistry, legacy.reportSectionRegistry)
        for object in legacy.objects {
            XCTAssertEqual(release.manifest.objects.first(where: { $0.typeID == object.typeID }), object)
        }
        for value in legacy.enums {
            XCTAssertEqual(release.manifest.enums.first(where: { $0.typeID == value.typeID }), value)
        }
        XCTAssertThrowsError(try release.admitFrozenManifest(legacy)) { error in
            XCTAssertEqual(error as? Failure, .unsupportedManifest)
        }
        let copy = try resourceBundle()
        try originalBytes.write(to: XCTUnwrap(copy.files[Release.manifestResource.fileName]))
        assertFailure(.invalidResource(Release.manifestResource.fileName), bundle: copy.bundle)
    }

    func testActualBundleLookupSupportsFlattenedAndPreservedResourceLayouts() throws {
        let expected = try Release.loadBundled().manifest
        for flattened in [true, false] {
            let copy = try resourceBundle(flattened: flattened)
            XCTAssertEqual(try Release.loadBundled(bundle: copy.bundle).manifest, expected)
        }
    }

    func testMissingAndRenamedResourcesCannotFallBackToAnotherBundle() throws {
        for resource in resources {
            let copy = try resourceBundle()
            let url = try XCTUnwrap(copy.files[resource.fileName])
            try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("wrong-identity"))
            assertFailure(.resourceMissing(resource.fileName), bundle: copy.bundle)
        }
    }

    func testDuplicateResourceIdentityFailsEvenWhenBothCopiesAreAuthentic() throws {
        for resource in resources {
            let copy = try resourceBundle()
            let directory = copy.root.appendingPathComponent("duplicate", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: XCTUnwrap(copy.files[resource.fileName]),
                to: directory.appendingPathComponent(resource.fileName))
            assertFailure(.resourceAmbiguous(resource.fileName), bundle: copy.bundle)
        }
    }

    func testTruncatedOversizedAndSameSizeTamperedResourcesFailAtRealLoader() throws {
        for resource in resources {
            for mutation in 0..<3 {
                let copy = try resourceBundle()
                let url = try XCTUnwrap(copy.files[resource.fileName])
                var bytes = try Data(contentsOf: url)
                switch mutation {
                case 0: bytes.removeLast()
                case 1: bytes.append(0x20)
                default: bytes[bytes.startIndex + 20] ^= 1
                }
                try bytes.write(to: url)
                assertFailure(.invalidResource(resource.fileName), bundle: copy.bundle)
            }
        }
    }

    func testSchemaResourceIdentityCannotBeSwappedAndManifestIdentityCannotBeRewritten() throws {
        let copy = try resourceBundle()
        let fileURL = try XCTUnwrap(copy.files[Release.fileSchemaResource.fileName])
        let reportURL = try XCTUnwrap(copy.files[Release.reportSchemaResource.fileName])
        try Data(contentsOf: reportURL).write(to: fileURL)
        assertFailure(.invalidResource(Release.fileSchemaResource.fileName), bundle: copy.bundle)

        let identityCopy = try resourceBundle()
        let manifestURL = try XCTUnwrap(identityCopy.files[Release.manifestResource.fileName])
        let text = try String(contentsOf: manifestURL, encoding: .utf8)
        let rewritten = text.replacingOccurrences(of: "\"manifestID\":\"activity-completed-contract-manifest-v1\"",
            with: "\"manifestID\":\"activity-completed-contract-manifest-v2\"")
        XCTAssertNotEqual(rewritten, text)
        try Data(rewritten.utf8).write(to: manifestURL)
        assertFailure(.invalidResource(Release.manifestResource.fileName), bundle: identityCopy.bundle)
    }

    func testSymlinkedResourceIsNotAnAppOwnedResource() throws {
        let copy = try resourceBundle()
        let url = try XCTUnwrap(copy.files[Release.manifestResource.fileName])
        let target = copy.root.appendingPathComponent("relocated.json")
        try FileManager.default.moveItem(at: url, to: target)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target.path)
        assertFailure(.invalidResource(Release.manifestResource.fileName), bundle: copy.bundle)
    }

    func testFrozenReadbackRejectsWrongIdentityVersionReaderRegistryAndIncompleteCatalog() throws {
        let release = try Release.loadBundled()
        let manifest = release.manifest
        let widerReaders = try ContractCompatibilityRuleV1(
            minimumReaderVersion: 2, maximumReaderVersion: 3, unknownObjectFields: .reject)
        let changedRegistry = try ReportSectionRegistryV1(registryID: "unpublished-report-sections",
            registryVersion: 1, sections: manifest.reportSectionRegistry.sections)
        var changedRoots: [ContractObjectDefinitionV1] = []
        for object in manifest.objects {
            if object.typeID == Release.fileRootTypeID {
                changedRoots.append(try ContractObjectDefinitionV1(typeID: object.typeID, version: 2,
                    unknownFieldPolicy: object.unknownFieldPolicy, fields: object.fields))
            } else { changedRoots.append(object) }
        }
        var changedDefinition = manifest.objects
        let otherIndex = try XCTUnwrap(changedDefinition.firstIndex(where: {
            $0.typeID != Release.fileRootTypeID && $0.typeID != Release.reportRootTypeID
        }))
        let other = changedDefinition[otherIndex]
        changedDefinition[otherIndex] = try ContractObjectDefinitionV1(typeID: other.typeID,
            version: other.version + 1, unknownFieldPolicy: other.unknownFieldPolicy, fields: other.fields)
        let withoutReport = manifest.objects.filter { $0.typeID != Release.reportRootTypeID }
        let variants: [ContractManifestV1] = [
            try variant(manifest, identity: "unpublished-completed-release"),
            try variant(manifest, version: 2),
            try variant(manifest, compatibility: widerReaders),
            try variant(manifest, objects: changedRoots),
            try variant(manifest, objects: changedDefinition),
            try variant(manifest, objects: withoutReport),
            try variant(manifest, registry: changedRegistry)
        ]
        for candidate in variants {
            try candidate.validate() // Generic validity cannot confer release admission.
            XCTAssertThrowsError(try release.admitFrozenManifest(candidate)) { error in
                XCTAssertEqual(error as? Failure, .unsupportedManifest)
            }
        }
    }
}
