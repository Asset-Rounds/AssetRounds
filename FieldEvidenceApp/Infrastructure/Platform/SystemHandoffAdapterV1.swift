import Foundation
import UIKit

/// C46 platform boundary: a durable `SystemHandoffIntentV1` authorizes only
/// one explicit foreground presentation attempt. Destination and outcome stay
/// ephemeral, and this adapter never records sent, delivered, or arrival truth.
enum C46SystemHandoffPlatformBoundaryV1 {
    static let systemCallCountPerExplicitTap = 1
    static let outcomeIsCanonicalHistory = false
}

enum SystemHandoffURLFailureV1: Error, Equatable {
    case invalidDestination
}

enum SystemHandoffURLBuilderV1 {
    static func url(for request: SystemHandoffRequestV1) throws -> URL {
        try request.destination.validate(for: request.intent.kind)
        switch request.destination {
        case let .geographicCoordinate(latitude, longitude):
            let lat = fixedMicrodegrees(latitude)
            let lon = fixedMicrodegrees(longitude)
            return try mapsURL(destination: "\(lat),\(lon)")
        case let .exactAddress(address):
            return try mapsURL(destination: address)
        case let .phone(value):
            let number = try normalizedPhone(value)
            let scheme = request.intent.kind == .call ? "tel" : "sms"
            guard let url = URL(string: "\(scheme):\(number)") else {
                throw SystemHandoffURLFailureV1.invalidDestination
            }
            return url
        case let .email(value):
            guard request.intent.kind == .email,
                  isSafeEmail(value) else {
                throw SystemHandoffURLFailureV1.invalidDestination
            }
            let recipient = percentEncodedMailtoRecipient(value)
            guard let url = URL(string: "mailto:\(recipient)"),
                  url.scheme == "mailto",
                  url.query == nil,
                  url.fragment == nil else {
                throw SystemHandoffURLFailureV1.invalidDestination
            }
            return url
        }
    }

    private static func mapsURL(destination: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "daddr", value: destination)]
        guard let url = components.url else {
            throw SystemHandoffURLFailureV1.invalidDestination
        }
        return url
    }

    private static func fixedMicrodegrees(_ value: Int32) -> String {
        let negative = value < 0
        let magnitude = Int64(value).magnitude
        let whole = magnitude / 1_000_000
        let fraction = magnitude % 1_000_000
        let digits = String(fraction)
        let padded = String(repeating: "0", count: 6 - digits.count) + digits
        return "\(negative ? "-" : "")\(whole).\(padded)"
    }

    private static func normalizedPhone(_ value: String) throws -> String {
        let scalars = value.unicodeScalars
        let hasLeadingPlus = scalars.first?.value == 0x2b
        let digits = scalars.filter { CharacterSet.decimalDigits.contains($0) }
        guard !digits.isEmpty, digits.count <= 32,
              digits.allSatisfy({ $0.isASCII }) else {
            throw SystemHandoffURLFailureV1.invalidDestination
        }
        return (hasLeadingPlus ? "+" : "") + String(String.UnicodeScalarView(digits))
    }

    private static func isSafeEmail(_ value: String) -> Bool {
        guard value.utf8.count <= 254,
              value == value.precomposedStringWithCanonicalMapping,
              !value.contains(".."),
              value.first != ".", value.last != ".",
              !value.contains("?"), !value.contains("#"),
              !value.contains("&"), !value.contains(","),
              !value.contains(";"), !value.contains(":"),
              !value.contains("/"), !value.contains("\\"),
              !value.contains("\r"), !value.contains("\n") else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              parts[1].contains(".") else { return false }
        let forbidden = CharacterSet.whitespacesAndNewlines
            .union(.controlCharacters)
            .union(.illegalCharacters)
        return value.unicodeScalars.allSatisfy { !forbidden.contains($0) }
            && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }

    /// RFC 6068 recipient-only encoding over the exact NFC UTF-8 bytes. Only
    /// unreserved bytes plus the single address separator remain literal;
    /// therefore Unicode, percent signs, and URI delimiters cannot introduce
    /// subject/body/query/fragment fields.
    private static func percentEncodedMailtoRecipient(_ value: String) -> String {
        let hexadecimal = Array("0123456789ABCDEF".utf8)
        var output = [UInt8]()
        output.reserveCapacity(value.utf8.count * 3)
        for byte in value.utf8 {
            let unreserved = (0x41...0x5A).contains(byte)
                || (0x61...0x7A).contains(byte)
                || (0x30...0x39).contains(byte)
                || [0x2D, 0x2E, 0x5F, 0x7E, 0x40].contains(byte)
            if unreserved {
                output.append(byte)
            } else {
                output.append(0x25)
                output.append(hexadecimal[Int(byte >> 4)])
                output.append(hexadecimal[Int(byte & 0x0F)])
            }
        }
        return String(decoding: output, as: UTF8.self)
    }
}

@MainActor
protocol SystemURLHandoffOpeningV1: AnyObject {
    var canPresentSystemHandoff: Bool { get }
    func openOnce(_ url: URL) async -> Bool
}

@MainActor
final class UIApplicationSystemURLHandoffOpenerV1: SystemURLHandoffOpeningV1 {
    var canPresentSystemHandoff: Bool {
        UIApplication.shared.applicationState == .active
    }

    func openOnce(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url, options: [:])
    }
}

/// Presents one user-directed OS handoff. It performs no canOpenURL probe,
/// retry, alternate-target selection, background work, or result persistence.
@MainActor
final class SystemHandoffAdapterV1: SystemHandoffPortV1 {
    private let opener: any SystemURLHandoffOpeningV1
    private let clock: any ApplicationClock

    init(
        opener: any SystemURLHandoffOpeningV1,
        clock: any ApplicationClock
    ) {
        self.opener = opener
        self.clock = clock
    }

    convenience init(clock: any ApplicationClock) {
        self.init(opener: UIApplicationSystemURLHandoffOpenerV1(), clock: clock)
    }

    func handOff(_ request: SystemHandoffRequestV1) async -> SystemHandoffResultV1 {
        let revision = request.currentTarget.expectedRevision
        guard !Task.isCancelled else {
            return result(request, .cancelledBeforeHandoff, revision)
        }
        guard opener.canPresentSystemHandoff else {
            return result(request, .systemUnavailable, revision)
        }
        let url: URL
        do {
            url = try SystemHandoffURLBuilderV1.url(for: request)
        } catch {
            return result(request, .targetInvalid, revision)
        }
        guard !Task.isCancelled else {
            return result(request, .cancelledBeforeHandoff, revision)
        }
        let accepted = await opener.openOnce(url)
        return result(
            request,
            accepted ? .handedOffToSystem : .systemRejected,
            revision
        )
    }

    private func result(
        _ request: SystemHandoffRequestV1,
        _ disposition: SystemHandoffDispositionV1,
        _ revision: UInt64
    ) -> SystemHandoffResultV1 {
        do {
            return try SystemHandoffResultV1(
                intentID: request.intent.intentID,
                disposition: disposition,
                evaluatedAt: clock.now(),
                resolvedTargetRevision: revision
            )
        } catch {
            // SystemHandoffRequestV1 already validates the same nonzero intent
            // ID and positive target revision. Reaching this branch indicates
            // a violated core invariant rather than a recoverable OS outcome.
            preconditionFailure("Validated handoff request produced an invalid result")
        }
    }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Platform_SystemHandoffAdapterV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}
