import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Proves a restored or upgraded store admits the canonical writer: activation
/// runs recoverBeforeWriterActivation, so validateAll (mutable semantic
/// checkpoint v2 included) must pass. The writer is released afterwards.
@MainActor
func assertCanonicalWriterActivatesV1(
    _ session: StoreGenerationSession,
    _ label: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        try coordinator.invalidateAndReleaseWriter()
    } catch {
        XCTFail("\(label): canonical writer activation failed: \(error)", file: file, line: line)
    }
}
