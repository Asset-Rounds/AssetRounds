import Foundation

/// Fail-closed outcomes for byte-exact authored Unicode preservation checks.
enum UnicodeEvidenceSafetyFailureV1: Error, Equatable, Sendable {
    case invalidUTF8
    case changedSource
    case changedBytes
}

/// A non-mutating inventory of a string's authored Unicode representation.
struct UnicodeEvidenceIdentityV1: Equatable, Sendable {
    let utf8SHA256: String
    let utf8ByteCount: Int
    let scalarCount: Int
    let graphemeCount: Int
    /// Bidi controls are retained as diagnostics; they are never sanitized.
    let directionalControls: [UnicodeDirectionalControlV1]
}

/// The scalar offset is in `String.UnicodeScalarView`, never UTF-16 units.
struct UnicodeDirectionalControlV1: Equatable, Sendable {
    let scalarOffset: Int
    let scalarValue: UInt32
}

/// Preserves the exact authored UTF-8 representation at product boundaries.
/// Swift `String` equality is canonically equivalent, so it cannot prove that
/// a decomposed or otherwise authored scalar sequence survived unchanged.
/// Diagnostic directional-control reporting never authorizes an alteration;
/// C03 owns bidirectional UI semantics.
enum UnicodeEvidenceSafetyV1 {
    private static let directionalControlScalars: Set<UInt32> = [
        0x061C, // Arabic Letter Mark
        0x200E, // Left-to-Right Mark
        0x200F, // Right-to-Left Mark
        0x202A, // Left-to-Right Embedding
        0x202B, // Right-to-Left Embedding
        0x202C, // Pop Directional Formatting
        0x202D, // Left-to-Right Override
        0x202E, // Right-to-Left Override
        0x2066, // Left-to-Right Isolate
        0x2067, // Right-to-Left Isolate
        0x2068, // First Strong Isolate
        0x2069, // Pop Directional Isolate
    ]

    static func identity(of value: String) -> UnicodeEvidenceIdentityV1 {
        let bytes = Data(value.utf8)
        let controls = value.unicodeScalars.enumerated().compactMap { offset, scalar in
            directionalControlScalars.contains(scalar.value)
                ? UnicodeDirectionalControlV1(
                    scalarOffset: offset,
                    scalarValue: scalar.value
                )
                : nil
        }
        return UnicodeEvidenceIdentityV1(
            utf8SHA256: KernelCanonicalHashV1.sha256(bytes),
            utf8ByteCount: bytes.count,
            scalarCount: value.unicodeScalars.count,
            graphemeCount: value.count,
            directionalControls: controls
        )
    }

    static func validatedUTF8(_ bytes: Data) throws -> String {
        // Decode code units directly so an authored leading U+FEFF remains a
        // scalar. The exact round trip rejects every repaired invalid sequence;
        // replacement text is never returned to the caller.
        let result = String(decoding: bytes, as: UTF8.self)
        guard Data(result.utf8) == bytes else {
            throw UnicodeEvidenceSafetyFailureV1.invalidUTF8
        }
        return result
    }

    static func requireExactSource(
        before: String,
        after: String
    ) throws -> UnicodeEvidenceIdentityV1 {
        guard Data(before.utf8) == Data(after.utf8) else {
            throw UnicodeEvidenceSafetyFailureV1.changedSource
        }
        return identity(of: after)
    }

    static func requireExactBytes(before: Data, after: Data) throws {
        guard before == after else {
            throw UnicodeEvidenceSafetyFailureV1.changedBytes
        }
    }
}
