import Foundation

enum AssistedInputCapabilityFailureV1: Error, Equatable { case invalidObservation, environmentUnavailable }

enum AssistedInputKindV1: String, CaseIterable, Sendable {
    case ocr, dictation, speechRecognition, grammar
}

/// Nonpersistent observations. Model identifiers are not device identifiers;
/// no serial number, account, authored text, audio, or image is collected.
struct AssistedInputEnvironmentV1: Equatable, Sendable {
    let operatingSystemVersion: String
    let operatingSystemBuild: String
    let deviceModel: String
    let applicationBuild: String
    let isSimulator: Bool

    init(operatingSystemVersion: String, operatingSystemBuild: String, deviceModel: String,
         applicationBuild: String, isSimulator: Bool) throws {
        for value in [operatingSystemVersion, operatingSystemBuild, deviceModel, applicationBuild] {
            try AssistanceLimitsV1.token(value)
        }
        self.operatingSystemVersion = operatingSystemVersion
        self.operatingSystemBuild = operatingSystemBuild
        self.deviceModel = deviceModel
        self.applicationBuild = applicationBuild
        self.isSimulator = isSimulator
    }
}

struct AssistedInputCapabilityQueryV1: Equatable, Sendable {
    /// New for every probe, including retries of the same content request.
    let invocationID: UUID
    let kind: AssistedInputKindV1
    let localeIdentifiers: [String]
    let providerRelease: String
    let environment: AssistedInputEnvironmentV1

    init(invocationID: UUID = UUID(), kind: AssistedInputKindV1, localeIdentifiers: [String],
         providerRelease: String, environment: AssistedInputEnvironmentV1) throws {
        let locales = localeIdentifiers.sorted()
        guard invocationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              !locales.isEmpty, locales.count <= 32, Set(locales).count == locales.count else {
            throw AssistedInputCapabilityFailureV1.invalidObservation
        }
        try locales.forEach(AssistanceLimitsV1.token)
        try AssistanceLimitsV1.token(providerRelease)
        self.invocationID = invocationID; self.kind = kind; self.localeIdentifiers = locales
        self.providerRelease = providerRelease; self.environment = environment
    }
}

enum AssistedInputSupportV1: String, Sendable {
    case available, unavailable, unobserved
}

struct AssistedInputCapabilityObservationV1: Equatable, Sendable {
    let query: AssistedInputCapabilityQueryV1
    let supportedLocaleIdentifiers: [String]
    let onDevice: AssistedInputSupportV1
    let implementationRevision: String
    /// A working on-device recognizer does not establish online support, and
    /// network reachability never establishes a recognition capability.
    let online: AssistedInputSupportV1

    init(query: AssistedInputCapabilityQueryV1, supportedLocaleIdentifiers: [String],
         onDevice: AssistedInputSupportV1, online: AssistedInputSupportV1,
         implementationRevision: String) throws {
        let locales = supportedLocaleIdentifiers.sorted()
        guard locales.count <= 512, Set(locales).count == locales.count else {
            throw AssistedInputCapabilityFailureV1.invalidObservation
        }
        try locales.forEach(AssistanceLimitsV1.token)
        try AssistanceLimitsV1.token(implementationRevision)
        self.query = query; self.supportedLocaleIdentifiers = locales
        self.onDevice = onDevice; self.online = online
        self.implementationRevision = implementationRevision
    }
}

enum AssistedInputCapabilityDispositionV1: String, Sendable {
    case availableOnDevice, onlineOnly, unsupportedLocale, unavailable, unobserved
    case staleObservation, featureDisabled
    var mayStartOnDevice: Bool { self == .availableOnDevice }
}

typealias AssistedInputCapabilityProbeV1 = @Sendable (AssistedInputCapabilityQueryV1) async throws -> AssistedInputCapabilityObservationV1?
typealias AssistedInputEnvironmentProbeV1 = @Sendable () throws -> AssistedInputEnvironmentV1
