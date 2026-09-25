import Foundation
import XCTest

/// Locates JSON fixtures stored under `FieldEvidenceAppTests/Fixtures/...`.
///
/// FieldEvidenceAppTests is a file-system-synchronized group, so its resources
/// are copied flat into the .xctest bundle and a `subdirectory:` lookup returns
/// nil. The locator tries, in order: the flat bundle resource, the bundle
/// subdirectory (in case the layout is ever preserved), then the source file
/// next to this helper (`#filePath`), which the Simulator can read on the host.
enum TestFixtureLocatorV1 {
    private final class BundleMarker {}

    /// - Parameters:
    ///   - name: resource name without extension.
    ///   - ext: file extension, for example "json".
    ///   - subdirectory: path relative to `FieldEvidenceAppTests`, for example "Fixtures/V21/Content".
    static func url(
        _ name: String,
        withExtension ext: String,
        subdirectory: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let bundle = Foundation.Bundle(for: BundleMarker.self)
        if let flat = bundle.url(forResource: name, withExtension: ext) {
            return flat
        }
        if let nested = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return nested
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(subdirectory)
            .appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: source.path) {
            return source
        }
        XCTFail(
            "TestFixtureLocatorV1: fixture \(name).\(ext) not found flat in the test bundle, in bundle subdirectory \(subdirectory), or at \(source.path)",
            file: file,
            line: line
        )
        throw TestFixtureLocatorErrorV1.missing(name: name, subdirectory: subdirectory)
    }
}

enum TestFixtureLocatorErrorV1: Error, Equatable {
    case missing(name: String, subdirectory: String)
}
