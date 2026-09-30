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
              let data = try? Data(contentsOf: url),
              case let .available(pack) = load(data: data),
              pack == .illuminatedSignV1 else {
            return .unavailable
        }

        return .available(pack)
    }

    static func load(data: Data) -> SignPackLoadResult {
        let decoder = JSONDecoder()

        guard let decoded = try? decoder.decode(SignPack.self, from: data),
              valid(decoded),
              let normalizedCandidate = normalizedJSON(data),
              let expectedData = try? JSONEncoder().encode(decoded),
              let normalizedExpected = normalizedJSON(expectedData),
              jsonMemberCount(in: data) == jsonMemberCount(in: expectedData),
              normalizedCandidate == normalizedExpected else {
            return .unavailable
        }

        return .available(decoded)
    }

    /// Shared with the shipping adapter so V2 publication cannot accept a
    /// structurally plausible pack that the established V1 loader rejects.
    static func valid(_ pack: SignPack) -> Bool {
        let purposeKeys = ["wide_context", "close_detail", "work_context"]
        let acknowledgementKeys = ["after_dark", "safe_authorized_position"]
        let issueKeys = [
            "dark_section",
            "dim_or_uneven",
            "flicker_or_intermittent",
            "color_mismatch",
            "physical_damage",
            "other_visible_condition",
        ]
        let couldNotVerifyKeys = [
            "conditions_changed",
            "access_lost",
            "unsafe_to_continue",
            "required_view_obstructed",
            "capture_unavailable",
            "other",
        ]
        let stageKeys = ["check", "recheck"]
        let outcomeKeys = [
            "no_visible_issue",
            "visible_issue",
            "could_not_verify",
            "resolved",
            "issue_still_visible",
            "original_resolved_different_issue",
        ]

        guard pack.schemaVersion == 1,
              pack.contentVersion > 0,
              validLowercaseIdentifier(pack.packID, maximumLength: 200),
              validNoun(pack.nouns.asset),
              validNoun(pack.nouns.check),
              validNoun(pack.nouns.issue),
              pack.evidencePurposes.map(\.key) == purposeKeys,
              pack.evidencePurposes.allSatisfy({
                  validLowercaseIdentifier($0.key, maximumLength: 100)
                      && validText($0.display, maximumLength: 200)
                      && validText($0.instruction, maximumLength: 1_000)
              }),
              unique(pack.evidencePurposes.map(\.display)),
              unique(pack.evidencePurposes.map(\.instruction)),
              pack.acknowledgements.map(\.key) == acknowledgementKeys,
              pack.acknowledgements.allSatisfy({
                  validLowercaseIdentifier($0.key, maximumLength: 100)
                      && validText($0.copy, maximumLength: 1_000)
                      && validToken($0.version, maximumLength: 200)
              }),
              unique(pack.acknowledgements.map(\.copy)),
              validRegistry(pack.issueLabels, expectedKeys: issueKeys),
              validToken(pack.couldNotVerifyReasons.version, maximumLength: 200),
              validRegistry(
                  pack.couldNotVerifyReasons.entries,
                  expectedKeys: couldNotVerifyKeys
              ),
              validRegistry(pack.stageDisplays, expectedKeys: stageKeys),
              validRegistry(pack.outcomeDisplays, expectedKeys: outcomeKeys),
              validText(pack.disclaimer, maximumLength: 2_000) else {
            return false
        }

        return true
    }

    private static func validNoun(_ noun: SignPack.DisplayNoun) -> Bool {
        validText(noun.singular, maximumLength: 100)
            && validText(noun.plural, maximumLength: 100)
            && noun.singular != noun.plural
    }

    private static func validRegistry(
        _ entries: [SignPack.RegistryEntry],
        expectedKeys: [String]
    ) -> Bool {
        entries.map(\.key) == expectedKeys
            && entries.allSatisfy {
                validLowercaseIdentifier($0.key, maximumLength: 100)
                    && validText($0.display, maximumLength: 300)
            }
            && unique(entries.map(\.display))
    }

    private static func validLowercaseIdentifier(
        _ value: String,
        maximumLength: Int
    ) -> Bool {
        value == value.lowercased()
            && validToken(value, maximumLength: maximumLength)
    }

    private static func validToken(_ value: String, maximumLength: Int) -> Bool {
        guard validText(value, maximumLength: maximumLength) else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0)
                || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0)
                || $0 == 0x2D
                || $0 == 0x2E
                || $0 == 0x5F
        }
    }

    private static func validText(_ value: String, maximumLength: Int) -> Bool {
        value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.isEmpty
            && value.count <= maximumLength
            && value == value.precomposedStringWithCanonicalMapping
            && !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
    }

    private static func unique(_ values: [String]) -> Bool {
        Set(values).count == values.count
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
