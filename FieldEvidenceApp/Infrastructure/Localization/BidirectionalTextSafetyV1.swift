import Foundation

/// Display-only bidirectional isolation. This utility never normalizes,
/// persists, or changes the source/export representation.
enum BidirectionalTextSafetyV1 {
    private static let directionalControls: Set<UInt32> = [
        0x061C, 0x200E, 0x200F,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    static func naturalText(_ source: String) -> String {
        wrapParagraphs(visibleControls(source), opener: "\u{2068}", closer: "\u{2069}")
    }

    static func opaqueToken(_ source: String) -> String {
        wrapParagraphs(visibleControls(source, opaque: true), opener: "\u{2066}", closer: "\u{2069}")
    }

    static func visibleControls(_ source: String, opaque: Bool = false) -> String {
        source.unicodeScalars.map { scalar in
            if directionalControls.contains(scalar.value)
                || nonWhitespaceC0OrC1(scalar)
                || (opaque && scalar.properties.generalCategory == .format) {
                return visibleScalar(scalar)
            }
            return String(scalar)
        }.joined()
    }

    static func isPrintableASCII(_ source: String) -> Bool {
        source.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    }

    private static func nonWhitespaceC0OrC1(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value < 0x20 || (0x7F...0x9F).contains(value)) && !scalar.properties.isWhitespace
    }

    private static func visibleScalar(_ scalar: Unicode.Scalar) -> String {
        let hexadecimal = String(scalar.value, radix: 16, uppercase: true)
        return "[U+" + String(repeating: "0", count: max(0, 4 - hexadecimal.count)) + hexadecimal + "]"
    }

    private static func wrapParagraphs(
        _ source: String,
        opener: String,
        closer: String
    ) -> String {
        guard !source.isEmpty else { return "" }

        var result = ""
        var paragraph = ""
        for scalar in source.unicodeScalars {
            if isParagraphSeparator(scalar) {
                if !paragraph.isEmpty {
                    result += opener + paragraph + closer
                    paragraph = ""
                }
                result.unicodeScalars.append(scalar)
            } else {
                paragraph.unicodeScalars.append(scalar)
            }
        }
        if !paragraph.isEmpty {
            result += opener + paragraph + closer
        }
        return result
    }

    private static func isParagraphSeparator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x000A, 0x000B, 0x000C, 0x000D, 0x0085, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }
}