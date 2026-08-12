import Foundation

enum SignPackLoadResult: Equatable, Sendable {
    case available(SignPack)
    case unavailable

    var pack: SignPack? {
        guard case let .available(pack) = self else { return nil }
        return pack
    }
}

enum SignPackLoader {
    private static let resourceName = "IlluminatedSignPack"
    private static let resourceExtension = "json"

    static func loadBundled(bundle: Bundle = .main) -> SignPackLoadResult {
        guard let url = bundledURL(in: bundle),
              let data = try? Data(contentsOf: url) else {
            return .unavailable
        }

        return load(data: data)
    }

    static func load(data: Data) -> SignPackLoadResult {
        let decoder = JSONDecoder()

        guard let decoded = try? decoder.decode(SignPack.self, from: data),
              decoded == .illuminatedSignV1,
              let normalizedCandidate = normalizedJSON(data),
              let expectedData = try? JSONEncoder().encode(SignPack.illuminatedSignV1),
              let normalizedExpected = normalizedJSON(expectedData),
              jsonMemberCount(in: data) == jsonMemberCount(in: expectedData),
              normalizedCandidate == normalizedExpected else {
            return .unavailable
        }

        return .available(decoded)
    }

    private static func bundledURL(in bundle: Bundle) -> URL? {
        if let rootURL = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
            return rootURL
        }

        if let packsURL = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Packs"
        ) {
            return packsURL
        }

        return bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Resources/Packs"
        )
    }

    private static func normalizedJSON(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object) else {
            return nil
        }

        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// JSONSerialization normalizes duplicate object members to one value. Counting
    /// member separators before normalization keeps duplicate known keys fail-closed.
    private static func jsonMemberCount(in data: Data) -> Int? {
        var count = 0
        var isInsideString = false
        var isEscaped = false

        for byte in data {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if byte == 0x5C {
                    isEscaped = true
                } else if byte == 0x22 {
                    isInsideString = false
                }
            } else if byte == 0x22 {
                isInsideString = true
            } else if byte == 0x3A {
                count += 1
            }
        }

        return isInsideString ? nil : count
    }
}
