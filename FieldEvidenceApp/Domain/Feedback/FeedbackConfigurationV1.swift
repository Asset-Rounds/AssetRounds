import Foundation

struct FeedbackConfigurationV1: Equatable, Sendable {
    let supportAddress: String?

    static let production = FeedbackConfigurationV1(supportAddress: nil)
    static let uiTestFixture = FeedbackConfigurationV1(
        supportAddress: "support@example.invalid"
    )

    var validatedSupportAddress: String? {
        guard let supportAddress,
              Self.validEmailAddress(supportAddress) else {
            return nil
        }
        return supportAddress
    }

    func route(mailComposerAvailable: Bool) -> FeedbackRouteV1 {
        guard validatedSupportAddress != nil else { return .blocked }
        return mailComposerAvailable ? .composer : .unavailableFallback
    }

    private static func validEmailAddress(_ value: String) -> Bool {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.utf8.count <= 254,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            return false
        }

        let parts = value.split(
            separator: "@",
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else { return false }
        let local = String(parts[0])
        let domain = String(parts[1])
        guard !local.isEmpty,
              local.utf8.count <= 64,
              local.first != ".",
              local.last != ".",
              !local.contains(".."),
              local.unicodeScalars.allSatisfy(validLocalScalar),
              domain.contains(".") else {
            return false
        }

        let labels = domain.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        return labels.count >= 2 && labels.allSatisfy(validDomainLabel)
    }

    private static func validLocalScalar(_ scalar: UnicodeScalar) -> Bool {
        isASCIIAlphanumeric(scalar)
            || "!#$%&'*+-/=?^_`{|}~.".unicodeScalars.contains(scalar)
    }

    private static func validDomainLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty,
              label.utf8.count <= 63,
              let first = label.unicodeScalars.first,
              let last = label.unicodeScalars.last,
              isASCIIAlphanumeric(first),
              isASCIIAlphanumeric(last) else {
            return false
        }
        return label.unicodeScalars.allSatisfy {
            isASCIIAlphanumeric($0) || $0 == "-"
        }
    }

    private static func isASCIIAlphanumeric(
        _ scalar: UnicodeScalar
    ) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            true
        default:
            false
        }
    }
}

enum FeedbackRouteV1: Equatable, Sendable {
    case blocked
    case composer
    case unavailableFallback
}

enum FeedbackAttachmentChoiceV1: Equatable, Sendable {
    case attach
    case doNotAttach
}
