import CryptoKit
import Foundation

// MARK: - Released protocol identity

enum EncryptedPortableEnvelopeFailureV1: Error, Equatable, Sendable {
    case invalidPassphrase
    case passphraseConfirmationMismatch
    case invalidPublicHeader
    case unsupportedProtocol
    case unsupportedInnerKind
    case invalidFrameLayout
    case resourceLimitExceeded
    case integerOverflow
    case randomGenerationFailed
    case keyDerivationFailed
    case wrongPassphraseOrDamagedEnvelope
    case hostileInnerPackage
    case cancelled
}

enum EncryptedPortableEnvelopeExternalFailureV1: String, Error, Codable, CaseIterable, Hashable, Sendable {
    case cancelled = "CANCELLED"
    case resourceLimit = "RESOURCE_LIMIT"
    case unsupportedRelease = "UNSUPPORTED_RELEASE"
    case wrongPassphraseOrDamagedEnvelope = "WRONG_PASSPHRASE_OR_DAMAGED_ENVELOPE"
}

enum EncryptedPortableEnvelopeInnerKindV1: UInt8, Codable, CaseIterable, Hashable, Sendable {
    case workspaceBackup = 1
    case reviewRequest = 2
    case reviewResponse = 3

    var stableName: String {
        switch self {
        case .workspaceBackup: return "WORKSPACE_BACKUP"
        case .reviewRequest: return "REVIEW_REQUEST"
        case .reviewResponse: return "REVIEW_RESPONSE"
        }
    }

    /// Service-request packages remain a different released protocol and cannot
    /// be silently relabelled as one of the three encrypted-envelope kinds.
    static let acceptsServiceRequestKinds = false

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let match = Self.allCases.first(where: { $0.stableName == value }) else {
            throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
        }
        self = match
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stableName)
    }
}

struct EncryptedPortableEnvelopeInnerProtocolVersionV1: Codable, Equatable, Hashable, Sendable {
    static let v1 = EncryptedPortableEnvelopeInnerProtocolVersionV1(releasedRawValue: 1)
    let rawValue: UInt16

    init(_ rawValue: UInt16) throws {
        guard rawValue == Self.v1.rawValue else {
            throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
        }
        self.rawValue = rawValue
    }

    private init(releasedRawValue: UInt16) { rawValue = releasedRawValue }

    static func released(for kind: EncryptedPortableEnvelopeInnerKindV1) -> Self {
        switch kind {
        case .workspaceBackup, .reviewRequest, .reviewResponse: return .v1
        }
    }

    func validateReleased(for kind: EncryptedPortableEnvelopeInnerKindV1) throws {
        guard self == Self.released(for: kind) else {
            throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
        }
    }

    init(from decoder: Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(UInt16.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct EncryptedPortableEnvelopeProtocolReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let fileExtension = "arenvelope"
    static let uniformTypeIdentifier = "com.assetrounds.encrypted-envelope"
    static let mediaType = "application/vnd.assetrounds.encrypted-envelope"
    static let headerByteCount = 128
    static let frameHeaderByteCount = 12
    static let minimumFrameCount: UInt32 = 1
    static let maximumFrameCount: UInt32 = UInt32.max
    static let releaseIdentifier = "ASSETROUNDS_ENCRYPTED_PORTABLE_ENVELOPE_V1"
    static let magic = Data([0x41, 0x52, 0x45, 0x4e, 0x56, 0x30, 0x31, 0x00]) // ARENV01\0
    static let current = EncryptedPortableEnvelopeProtocolReleaseV1()

    let identifier: String
    let formatVersion: UInt16
    let headerBytes: UInt16
    let frameHeaderBytes: UInt16

    init(
        identifier: String = Self.releaseIdentifier,
        formatVersion: UInt16 = 1,
        headerBytes: UInt16 = UInt16(Self.headerByteCount),
        frameHeaderBytes: UInt16 = UInt16(Self.frameHeaderByteCount)
    ) {
        self.identifier = identifier
        self.formatVersion = formatVersion
        self.headerBytes = headerBytes
        self.frameHeaderBytes = frameHeaderBytes
    }

    func validateReleased() throws {
        guard self == Self.current else {
            throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case identifier, formatVersion, headerBytes, frameHeaderBytes
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            identifier: try c.decode(String.self, forKey: .identifier),
            formatVersion: try c.decode(UInt16.self, forKey: .formatVersion),
            headerBytes: try c.decode(UInt16.self, forKey: .headerBytes),
            frameHeaderBytes: try c.decode(UInt16.self, forKey: .frameHeaderBytes)
        )
        try validateReleased()
    }
}

struct EncryptedEnvelopeKDFProfileV1: Codable, Equatable, Hashable, Sendable {
    static let released = EncryptedEnvelopeKDFProfileV1()

    let profileID: UInt16
    let algorithm: String
    let pseudorandomFunction: String
    let iterationCount: UInt32
    let saltByteCount: UInt8
    let derivedKeyByteCount: UInt8

    init(
        profileID: UInt16 = 1,
        algorithm: String = "PBKDF2",
        pseudorandomFunction: String = "HMAC_SHA256",
        iterationCount: UInt32 = 600_000,
        saltByteCount: UInt8 = 32,
        derivedKeyByteCount: UInt8 = 32
    ) {
        self.profileID = profileID
        self.algorithm = algorithm
        self.pseudorandomFunction = pseudorandomFunction
        self.iterationCount = iterationCount
        self.saltByteCount = saltByteCount
        self.derivedKeyByteCount = derivedKeyByteCount
    }

    func validateReleased() throws {
        guard self == Self.released else {
            throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case profileID, algorithm, pseudorandomFunction, iterationCount, saltByteCount, derivedKeyByteCount
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            profileID: try c.decode(UInt16.self, forKey: .profileID),
            algorithm: try c.decode(String.self, forKey: .algorithm),
            pseudorandomFunction: try c.decode(String.self, forKey: .pseudorandomFunction),
            iterationCount: try c.decode(UInt32.self, forKey: .iterationCount),
            saltByteCount: try c.decode(UInt8.self, forKey: .saltByteCount),
            derivedKeyByteCount: try c.decode(UInt8.self, forKey: .derivedKeyByteCount)
        )
        try validateReleased()
    }
}

struct EncryptedEnvelopeAEADProfileV1: Codable, Equatable, Hashable, Sendable {
    static let released = EncryptedEnvelopeAEADProfileV1()

    let profileID: UInt16
    let algorithm: String
    let framePlaintextByteLimit: UInt32
    let authenticationTagByteCount: UInt8
    let noncePrefixByteCount: UInt8
    let nonceFrameIndexByteCount: UInt8

    init(
        profileID: UInt16 = 1,
        algorithm: String = "AES_256_GCM",
        framePlaintextByteLimit: UInt32 = 1_048_576,
        authenticationTagByteCount: UInt8 = 16,
        noncePrefixByteCount: UInt8 = 8,
        nonceFrameIndexByteCount: UInt8 = 4
    ) {
        self.profileID = profileID
        self.algorithm = algorithm
        self.framePlaintextByteLimit = framePlaintextByteLimit
        self.authenticationTagByteCount = authenticationTagByteCount
        self.noncePrefixByteCount = noncePrefixByteCount
        self.nonceFrameIndexByteCount = nonceFrameIndexByteCount
    }

    func validateReleased() throws {
        guard self == Self.released else {
            throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case profileID, algorithm, framePlaintextByteLimit, authenticationTagByteCount
        case noncePrefixByteCount, nonceFrameIndexByteCount
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            profileID: try c.decode(UInt16.self, forKey: .profileID),
            algorithm: try c.decode(String.self, forKey: .algorithm),
            framePlaintextByteLimit: try c.decode(UInt32.self, forKey: .framePlaintextByteLimit),
            authenticationTagByteCount: try c.decode(UInt8.self, forKey: .authenticationTagByteCount),
            noncePrefixByteCount: try c.decode(UInt8.self, forKey: .noncePrefixByteCount),
            nonceFrameIndexByteCount: try c.decode(UInt8.self, forKey: .nonceFrameIndexByteCount)
        )
        try validateReleased()
    }
}

// MARK: - Passphrases and ephemeral secret ownership

enum PassphrasePolicyV1 {
    static let minimumUnicodeScalarCount = 15
    static let maximumUnicodeScalarCount = 256
    static let maximumUTF8ByteCount = 1_024
    static let normalization = "NFC_UTF8"
    static let preservesSpacesAndCase = true
    static let requiresExactConfirmation = true

    static func normalizedUTF8(passphrase: String, confirmation: String) throws -> Data {
        guard passphrase == confirmation else {
            throw EncryptedPortableEnvelopeFailureV1.passphraseConfirmationMismatch
        }
        return try normalizedUTF8(passphrase: passphrase)
    }

    static func normalizedUTF8(passphrase: String) throws -> Data {
        let normalized = passphrase.precomposedStringWithCanonicalMapping
        let scalarCount = normalized.unicodeScalars.count
        let bytes = Data(normalized.utf8)
        guard (minimumUnicodeScalarCount...maximumUnicodeScalarCount).contains(scalarCount),
              bytes.count <= maximumUTF8ByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPassphrase
        }
        return bytes
    }
}

/// A deliberately non-Codable, non-Hashable, memory-only owner for normalized
/// passphrase bytes. Clearing is best effort because Swift and system crypto may
/// make temporary copies; no API exposes a persistable representation.
final class EphemeralPassphraseV1: @unchecked Sendable {
    private var bytes: ContiguousArray<UInt8>
    private let lock = NSLock()
    /// Memory-only identity used to prove an exact same-session retry reuses
    /// the same secret owner without hashing or persisting passphrase bytes.
    let memoryOwnerID = UUID()

    init(passphrase: String, confirmation: String) throws {
        bytes = ContiguousArray(try PassphrasePolicyV1.normalizedUTF8(
            passphrase: passphrase,
            confirmation: confirmation
        ))
    }

    /// Reader-only construction accepts every valid V1 passphrase without a
    /// fabricated confirmation. Creation continues to require exact confirmation.
    init(openingPassphrase: String) throws {
        bytes = ContiguousArray(try PassphrasePolicyV1.normalizedUTF8(
            passphrase: openingPassphrase
        ))
    }

    deinit { clear() }

    func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try bytes.withUnsafeBufferPointer { buffer in
            try body(UnsafeRawBufferPointer(buffer))
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        bytes.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            base.update(repeating: 0, count: buffer.count)
        }
        bytes.removeAll(keepingCapacity: false)
    }
}

/// Non-Codable derived-key storage with the same terminal clearing contract.
final class EphemeralEncryptedEnvelopeKeyV1: @unchecked Sendable {
    private var bytes: ContiguousArray<UInt8>
    private let lock = NSLock()

    init(bytes: Data) throws {
        guard bytes.count == Int(EncryptedEnvelopeKDFProfileV1.released.derivedKeyByteCount) else {
            throw EncryptedPortableEnvelopeFailureV1.keyDerivationFailed
        }
        self.bytes = ContiguousArray(bytes)
    }

    deinit { clear() }

    func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try bytes.withUnsafeBufferPointer { buffer in
            try body(UnsafeRawBufferPointer(buffer))
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        bytes.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            base.update(repeating: 0, count: buffer.count)
        }
        bytes.removeAll(keepingCapacity: false)
    }
}

enum EphemeralSecretHandlingDispositionV1: String, Codable, Hashable, Sendable {
    case memoryOnlyBestEffortClear = "MEMORY_ONLY_BEST_EFFORT_CLEAR_ON_ALL_TERMINAL_AND_LIFECYCLE_BOUNDARIES"

    static let released = EphemeralSecretHandlingDispositionV1.memoryOnlyBestEffortClear
    static let passphraseIsPersisted = false
    static let derivedKeyIsPersisted = false
    static let secretAppearsInReceipts = false
}

// MARK: - Strict canonical binary structures

struct EncryptedPortableEnvelopePublicHeaderV1: Codable, Equatable, Hashable, Sendable {
    let release: EncryptedPortableEnvelopeProtocolReleaseV1
    let innerKind: EncryptedPortableEnvelopeInnerKindV1
    let innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1
    let reviewProtectionMode: ReviewExchangeProtectionV1?
    let kdfProfile: EncryptedEnvelopeKDFProfileV1
    let aeadProfile: EncryptedEnvelopeAEADProfileV1
    let publicEnvelopeID: Data
    let declaredFrameCount: UInt32
    let declaredPlaintextByteCount: UInt64
    let declaredCiphertextByteCount: UInt64
    let salt: Data
    let noncePrefix: Data

    init(
        release: EncryptedPortableEnvelopeProtocolReleaseV1 = .current,
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1,
        reviewProtectionMode: ReviewExchangeProtectionV1?,
        kdfProfile: EncryptedEnvelopeKDFProfileV1 = .released,
        aeadProfile: EncryptedEnvelopeAEADProfileV1 = .released,
        publicEnvelopeID: Data,
        declaredFrameCount: UInt32,
        declaredPlaintextByteCount: UInt64,
        declaredCiphertextByteCount: UInt64,
        salt: Data,
        noncePrefix: Data
    ) throws {
        self.release = release
        self.innerKind = innerKind
        self.innerProtocolVersion = innerProtocolVersion
        self.reviewProtectionMode = reviewProtectionMode
        self.kdfProfile = kdfProfile
        self.aeadProfile = aeadProfile
        self.publicEnvelopeID = publicEnvelopeID
        self.declaredFrameCount = declaredFrameCount
        self.declaredPlaintextByteCount = declaredPlaintextByteCount
        self.declaredCiphertextByteCount = declaredCiphertextByteCount
        self.salt = salt
        self.noncePrefix = noncePrefix
        try validateReleased()
    }

    func validateReleased() throws {
        try release.validateReleased()
        try innerProtocolVersion.validateReleased(for: innerKind)
        switch innerKind {
        case .workspaceBackup:
            guard reviewProtectionMode == nil else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
        case .reviewRequest, .reviewResponse:
            guard reviewProtectionMode == .passphraseEncryptedV1 else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
        }
        try kdfProfile.validateReleased()
        try aeadProfile.validateReleased()
        let tagBytes = UInt64(aeadProfile.authenticationTagByteCount)
        let (tagTotal, tagOverflow) = UInt64(declaredFrameCount).multipliedReportingOverflow(by: tagBytes)
        let (expectedCiphertextBytes, ciphertextOverflow) = declaredPlaintextByteCount
            .addingReportingOverflow(tagTotal)
        guard declaredFrameCount > 0,
              publicEnvelopeID.count == 16,
              salt.count == Int(kdfProfile.saltByteCount),
              noncePrefix.count == Int(aeadProfile.noncePrefixByteCount),
              !tagOverflow, !ciphertextOverflow,
              declaredCiphertextByteCount == expectedCiphertextBytes,
              declaredFrameCount == try Self.canonicalFrameCount(
                plaintextByteCount: declaredPlaintextByteCount,
                frameByteLimit: UInt64(aeadProfile.framePlaintextByteLimit)
              ) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
    }

    static func canonicalFrameCount(plaintextByteCount: UInt64, frameByteLimit: UInt64) throws -> UInt32 {
        guard frameByteLimit > 0 else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        if plaintextByteCount == 0 { return 1 }
        let quotient = plaintextByteCount / frameByteLimit
        let remainder = plaintextByteCount % frameByteLimit
        let value = quotient + (remainder == 0 ? 0 : 1)
        guard value >= UInt64(EncryptedPortableEnvelopeProtocolReleaseV1.minimumFrameCount),
              value <= UInt64(EncryptedPortableEnvelopeProtocolReleaseV1.maximumFrameCount) else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        return UInt32(value)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case release, innerKind, innerProtocolVersion, reviewProtectionMode, kdfProfile
        case aeadProfile, publicEnvelopeID, declaredFrameCount, declaredPlaintextByteCount
        case declaredCiphertextByteCount, salt, noncePrefix
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            release: c.decode(EncryptedPortableEnvelopeProtocolReleaseV1.self, forKey: .release),
            innerKind: c.decode(EncryptedPortableEnvelopeInnerKindV1.self, forKey: .innerKind),
            innerProtocolVersion: c.decode(EncryptedPortableEnvelopeInnerProtocolVersionV1.self, forKey: .innerProtocolVersion),
            reviewProtectionMode: c.decodeIfPresent(ReviewExchangeProtectionV1.self, forKey: .reviewProtectionMode),
            kdfProfile: c.decode(EncryptedEnvelopeKDFProfileV1.self, forKey: .kdfProfile),
            aeadProfile: c.decode(EncryptedEnvelopeAEADProfileV1.self, forKey: .aeadProfile),
            publicEnvelopeID: c.decode(Data.self, forKey: .publicEnvelopeID),
            declaredFrameCount: c.decode(UInt32.self, forKey: .declaredFrameCount),
            declaredPlaintextByteCount: c.decode(UInt64.self, forKey: .declaredPlaintextByteCount),
            declaredCiphertextByteCount: c.decode(UInt64.self, forKey: .declaredCiphertextByteCount),
            salt: c.decode(Data.self, forKey: .salt),
            noncePrefix: c.decode(Data.self, forKey: .noncePrefix)
        )
    }
}

struct EncryptedPortableEnvelopeAuthenticatedManifestV1: Codable, Equatable, Sendable {
    let publicHeader: EncryptedPortableEnvelopePublicHeaderV1
    let canonicalHeaderBytes: Data
    let canonicalHeaderSHA256: Data
    let everyFrameAuthenticatesCanonicalHeader: Bool

    init(
        publicHeader: EncryptedPortableEnvelopePublicHeaderV1,
        canonicalHeaderBytes: Data
    ) throws {
        try publicHeader.validateReleased()
        let expectedHeaderBytes = try EncryptedPortableEnvelopeBinaryCodecV1.encodePublicHeader(
            publicHeader
        )
        let digest = Data(SHA256.hash(data: canonicalHeaderBytes))
        guard canonicalHeaderBytes.count
                == EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount,
              canonicalHeaderBytes == expectedHeaderBytes,
              digest.count == 32 else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        self.publicHeader = publicHeader
        self.canonicalHeaderBytes = canonicalHeaderBytes
        canonicalHeaderSHA256 = digest
        everyFrameAuthenticatesCanonicalHeader = true
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case publicHeader, canonicalHeaderBytes, canonicalHeaderSHA256
        case everyFrameAuthenticatesCanonicalHeader
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            publicHeader: c.decode(EncryptedPortableEnvelopePublicHeaderV1.self, forKey: .publicHeader),
            canonicalHeaderBytes: c.decode(Data.self, forKey: .canonicalHeaderBytes)
        )
        guard c.decode(Data.self, forKey: .canonicalHeaderSHA256) == canonicalHeaderSHA256,
              c.decode(Bool.self, forKey: .everyFrameAuthenticatesCanonicalHeader) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
    }
}

struct EncryptedEnvelopeFrameHeaderV1: Equatable, Hashable, Sendable {
    static let finalFlag: UInt8 = 0x01

    let index: UInt32
    let isFinal: Bool
    let ciphertextByteCount: UInt32

    init(index: UInt32, isFinal: Bool, ciphertextByteCount: UInt32) {
        self.index = index
        self.isFinal = isFinal
        self.ciphertextByteCount = ciphertextByteCount
    }

    func validate(for publicHeader: EncryptedPortableEnvelopePublicHeaderV1) throws {
        guard publicHeader.declaredFrameCount > 0 else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        let expectedFinalIndex = publicHeader.declaredFrameCount - 1
        let expectedFinal = index == expectedFinalIndex
        guard index < publicHeader.declaredFrameCount,
              isFinal == expectedFinal,
              ciphertextByteCount <= publicHeader.aeadProfile.framePlaintextByteLimit else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }

        let frameLimit = UInt64(publicHeader.aeadProfile.framePlaintextByteLimit)
        let expectedByteCount: UInt64
        if publicHeader.declaredPlaintextByteCount == 0 {
            expectedByteCount = 0
        } else if expectedFinal {
            let remainder = publicHeader.declaredPlaintextByteCount % frameLimit
            expectedByteCount = remainder == 0 ? frameLimit : remainder
        } else {
            expectedByteCount = frameLimit
        }
        guard UInt64(ciphertextByteCount) == expectedByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
    }
}

struct EncryptedEnvelopeSealedFrameV1: Equatable, Sendable {
    let header: EncryptedEnvelopeFrameHeaderV1
    let ciphertext: Data
    let authenticationTag: Data

    init(header: EncryptedEnvelopeFrameHeaderV1, ciphertext: Data, authenticationTag: Data) throws {
        guard ciphertext.count == Int(header.ciphertextByteCount),
              authenticationTag.count == Int(EncryptedEnvelopeAEADProfileV1.released.authenticationTagByteCount) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        self.header = header
        self.ciphertext = ciphertext
        self.authenticationTag = authenticationTag
    }

    func validateBinding(to publicHeader: EncryptedPortableEnvelopePublicHeaderV1) throws {
        try publicHeader.validateReleased()
        try header.validate(for: publicHeader)
        guard ciphertext.count == Int(header.ciphertextByteCount),
              authenticationTag.count == Int(publicHeader.aeadProfile.authenticationTagByteCount) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
    }
}

struct EncryptedPortableEnvelopeResourceLimitsV1: Codable, Equatable, Hashable, Sendable {
    /// The released operational admission profile is intentionally lower than
    /// the V1 wire domain's UInt32.max. It can reject a concrete operation for
    /// device-resource reasons but never redefines a structurally valid V1.
    static let maximumOperationalScratchByteCount: UInt64 = 4_294_967_296
    static let maximumOperationalPlaintextByteCount: UInt64 = 4_294_852_480
    static let released = EncryptedPortableEnvelopeResourceLimitsV1(
        maximumPlaintextByteCount: maximumOperationalPlaintextByteCount,
        maximumEnvelopeByteCount: maximumOperationalScratchByteCount,
        maximumFrameCount: 4_096
    )

    let maximumPlaintextByteCount: UInt64
    let maximumEnvelopeByteCount: UInt64
    let maximumFrameCount: UInt32

    init(maximumPlaintextByteCount: UInt64, maximumEnvelopeByteCount: UInt64, maximumFrameCount: UInt32) {
        self.maximumPlaintextByteCount = maximumPlaintextByteCount
        self.maximumEnvelopeByteCount = maximumEnvelopeByteCount
        self.maximumFrameCount = maximumFrameCount
    }

    func validate() throws {
        guard maximumFrameCount > 0,
              maximumFrameCount <= 4_096,
              maximumPlaintextByteCount <= Self.maximumOperationalPlaintextByteCount,
              maximumEnvelopeByteCount <= Self.maximumOperationalScratchByteCount,
              maximumPlaintextByteCount <= maximumEnvelopeByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
    }
}

protocol EncryptedEnvelopeBoundedSeekableSourceV1: Sendable {
    func encryptedEnvelopeByteCount() throws -> UInt64
    func readExactly(atOffset: UInt64, byteCount: Int) throws -> Data
}

protocol EncryptedEnvelopeProtectedScratchSinkV1: EncryptedEnvelopeBoundedSeekableSourceV1 {
    var protectionClass: EncryptedEnvelopeProtectionClassV1 { get }
    var isExcludedFromBackup: Bool { get }
    func prepareForStreamingWrite(expectedByteCount: UInt64) throws
    func appendStreamingBytes(_ bytes: Data) throws
    func synchronizeStreamingWrite() throws
    func discardStreamingBytes() throws
}

protocol EncryptedEnvelopeCancellationCheckingV1: Sendable {
    func checkCancellation() throws
}

struct EncryptedEnvelopeNoCancellationV1: EncryptedEnvelopeCancellationCheckingV1 {
    func checkCancellation() throws {}
}

typealias EncryptedEnvelopeStreamingInnerValidatorV1 = @Sendable (
    any EncryptedEnvelopeBoundedSeekableSourceV1,
    EncryptedPortableEnvelopeInnerKindV1,
    EncryptedPortableEnvelopeInnerProtocolVersionV1
) throws -> Void

struct EncryptedEnvelopeStructuralPreflightReceiptV1: Codable, Equatable, Hashable, Sendable {
    let protocolIdentifier: String
    let innerKind: EncryptedPortableEnvelopeInnerKindV1
    let innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1
    let reviewProtectionMode: ReviewExchangeProtectionV1?
    let frameCount: UInt32
    let plaintextByteCount: UInt64
    let ciphertextByteCount: UInt64
    let envelopeByteCount: UInt64
    let allIndicesContiguous: Bool
    let exactlyOneFinalFrame: Bool

    init(
        protocolIdentifier: String,
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1,
        reviewProtectionMode: ReviewExchangeProtectionV1?,
        frameCount: UInt32,
        plaintextByteCount: UInt64,
        ciphertextByteCount: UInt64,
        envelopeByteCount: UInt64,
        allIndicesContiguous: Bool = true,
        exactlyOneFinalFrame: Bool = true
    ) throws {
        let aead = EncryptedEnvelopeAEADProfileV1.released
        let release = EncryptedPortableEnvelopeProtocolReleaseV1.current
        let (tagTotal, tagOverflow) = UInt64(frameCount).multipliedReportingOverflow(
            by: UInt64(aead.authenticationTagByteCount)
        )
        let (expectedCiphertext, cipherOverflow) = plaintextByteCount.addingReportingOverflow(tagTotal)
        let (frameHeaders, frameOverflow) = UInt64(frameCount).multipliedReportingOverflow(
            by: UInt64(release.frameHeaderBytes)
        )
        let (withFrames, framedOverflow) = expectedCiphertext.addingReportingOverflow(frameHeaders)
        let (expectedEnvelope, envelopeOverflow) = UInt64(release.headerBytes)
            .addingReportingOverflow(withFrames)
        let canonicalFrameCount = try EncryptedPortableEnvelopePublicHeaderV1.canonicalFrameCount(
            plaintextByteCount: plaintextByteCount,
            frameByteLimit: UInt64(aead.framePlaintextByteLimit)
        )
        try innerProtocolVersion.validateReleased(for: innerKind)
        switch innerKind {
        case .workspaceBackup:
            guard reviewProtectionMode == nil else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
        case .reviewRequest, .reviewResponse:
            guard reviewProtectionMode == .passphraseEncryptedV1 else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
        }
        guard protocolIdentifier == release.identifier,
              frameCount == canonicalFrameCount,
              !tagOverflow, !cipherOverflow, !frameOverflow, !framedOverflow, !envelopeOverflow,
              ciphertextByteCount == expectedCiphertext,
              envelopeByteCount == expectedEnvelope,
              allIndicesContiguous, exactlyOneFinalFrame else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        self.protocolIdentifier = protocolIdentifier
        self.innerKind = innerKind
        self.innerProtocolVersion = innerProtocolVersion
        self.reviewProtectionMode = reviewProtectionMode
        self.frameCount = frameCount
        self.plaintextByteCount = plaintextByteCount
        self.ciphertextByteCount = ciphertextByteCount
        self.envelopeByteCount = envelopeByteCount
        self.allIndicesContiguous = allIndicesContiguous
        self.exactlyOneFinalFrame = exactlyOneFinalFrame
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolIdentifier, innerKind, innerProtocolVersion, reviewProtectionMode, frameCount
        case plaintextByteCount, ciphertextByteCount
        case envelopeByteCount, allIndicesContiguous, exactlyOneFinalFrame
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolIdentifier: c.decode(String.self, forKey: .protocolIdentifier),
            innerKind: c.decode(EncryptedPortableEnvelopeInnerKindV1.self, forKey: .innerKind),
            innerProtocolVersion: c.decode(EncryptedPortableEnvelopeInnerProtocolVersionV1.self, forKey: .innerProtocolVersion),
            reviewProtectionMode: c.decodeIfPresent(ReviewExchangeProtectionV1.self, forKey: .reviewProtectionMode),
            frameCount: c.decode(UInt32.self, forKey: .frameCount),
            plaintextByteCount: c.decode(UInt64.self, forKey: .plaintextByteCount),
            ciphertextByteCount: c.decode(UInt64.self, forKey: .ciphertextByteCount),
            envelopeByteCount: c.decode(UInt64.self, forKey: .envelopeByteCount),
            allIndicesContiguous: c.decode(Bool.self, forKey: .allIndicesContiguous),
            exactlyOneFinalFrame: c.decode(Bool.self, forKey: .exactlyOneFinalFrame)
        )
    }
}

// MARK: - Secret-free receipts and boundary truth

enum EncryptedEnvelopeProtectionClassV1: String, Codable, CaseIterable, Hashable, Sendable {
    case complete = "NSFILEPROTECTION_COMPLETE"
}

enum EncryptedEnvelopeValidationResultV1: String, Codable, CaseIterable, Hashable, Sendable {
    case passed = "PASSED"
    case pendingInnerValidation = "PENDING_INNER_HOSTILE_VALIDATION"
    case failed = "FAILED"
}

enum EncryptedEnvelopeTestResultV1: String, Codable, CaseIterable, Hashable, Sendable {
    case notRun = "NOT_RUN"
    case passed = "PASSED"
    case failed = "FAILED"
}

enum EncryptedEnvelopeCleanupDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case completed = "DERIVED_KEY_CLEARED_SCRATCH_CLEAN_LIFECYCLE_PASSPHRASE_NOT_PERSISTED"
    case pending = "CLEANUP_PENDING"
}

enum EncryptedEnvelopeErrorCategoryV1: String, Codable, CaseIterable, Hashable, Sendable {
    case none = "NONE"
    case structural = "STRUCTURAL_OR_RESOURCE_PREFLIGHT"
    case wrongPassphraseOrDamage = "WRONG_PASSPHRASE_OR_DAMAGED_ENVELOPE"
    case hostileInnerPackage = "HOSTILE_INNER_PACKAGE"
    case protectedData = "PROTECTED_DATA_UNAVAILABLE"
    case storage = "STORAGE_UNAVAILABLE"
    case interrupted = "INTERRUPTED"
    case cryptographicService = "CRYPTOGRAPHIC_SERVICE_FAILURE"

    static func classify(_ error: Error) -> EncryptedEnvelopeErrorCategoryV1 {
        guard let failure = error as? EncryptedPortableEnvelopeFailureV1 else {
            return .hostileInnerPackage
        }
        switch failure {
        case .wrongPassphraseOrDamagedEnvelope:
            return .wrongPassphraseOrDamage
        case .hostileInnerPackage:
            return .hostileInnerPackage
        case .resourceLimitExceeded, .integerOverflow, .invalidPublicHeader,
             .invalidFrameLayout, .unsupportedProtocol, .unsupportedInnerKind:
            return .structural
        case .randomGenerationFailed, .keyDerivationFailed:
            return .cryptographicService
        case .cancelled:
            return .interrupted
        case .invalidPassphrase, .passphraseConfirmationMismatch:
            return .wrongPassphraseOrDamage
        }
    }

    static func externalFailure(for error: Error) -> EncryptedPortableEnvelopeExternalFailureV1 {
        if let external = error as? EncryptedPortableEnvelopeExternalFailureV1 {
            return external
        }
        switch classify(error) {
        case .wrongPassphraseOrDamage:
            return .wrongPassphraseOrDamagedEnvelope
        case .hostileInnerPackage:
            return .wrongPassphraseOrDamagedEnvelope
        case .structural:
            if let failure = error as? EncryptedPortableEnvelopeFailureV1 {
                switch failure {
                case .unsupportedProtocol, .unsupportedInnerKind: return .unsupportedRelease
                case .resourceLimitExceeded, .integerOverflow: return .resourceLimit
                case .cancelled: return .cancelled
                default: break
                }
            }
            return .wrongPassphraseOrDamagedEnvelope
        case .cryptographicService:
            return .wrongPassphraseOrDamagedEnvelope
        case .protectedData, .storage:
            return .resourceLimit
        case .interrupted:
            return .cancelled
        case .none:
            return .wrongPassphraseOrDamagedEnvelope
        }
    }
}

struct EncryptedEnvelopeOperationReceiptContextV1: Equatable, Hashable, Sendable {
    let operationID: UUID
    let attemptID: UUID
    let sourceProtectionClass: EncryptedEnvelopeProtectionClassV1
    let destinationProtectionClass: EncryptedEnvelopeProtectionClassV1
    let candidateHead: String
    let candidateTree: String
    let toolchainIdentifier: String
    let deterministicTestResult: EncryptedEnvelopeTestResultV1

    init(
        operationID: UUID,
        attemptID: UUID,
        sourceProtectionClass: EncryptedEnvelopeProtectionClassV1 = .complete,
        destinationProtectionClass: EncryptedEnvelopeProtectionClassV1 = .complete,
        candidateHead: String,
        candidateTree: String,
        toolchainIdentifier: String,
        deterministicTestResult: EncryptedEnvelopeTestResultV1 = .notRun
    ) throws {
        guard operationID != Self.zeroUUID,
              attemptID != Self.zeroUUID,
              Self.isGitOID(candidateHead),
              Self.isGitOID(candidateTree),
              !toolchainIdentifier.isEmpty,
              toolchainIdentifier.utf8.count <= 256 else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        self.operationID = operationID
        self.attemptID = attemptID
        self.sourceProtectionClass = sourceProtectionClass
        self.destinationProtectionClass = destinationProtectionClass
        self.candidateHead = candidateHead.lowercased()
        self.candidateTree = candidateTree.lowercased()
        self.toolchainIdentifier = toolchainIdentifier
        self.deterministicTestResult = deterministicTestResult
    }

    private static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    private static func isGitOID(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64)
            && value.unicodeScalars.allSatisfy {
                (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
            }
    }
}

struct EncryptedEnvelopeSealCryptographicFactsV1: Equatable, Sendable {
    let context: EncryptedEnvelopeOperationReceiptContextV1
    let publicHeader: EncryptedPortableEnvelopePublicHeaderV1
    let authenticatedManifest: EncryptedPortableEnvelopeAuthenticatedManifestV1
    let canonicalHeaderSHA256: Data
    let encryptedFileSHA256: Data
    let plaintextSHA256: Data
    let envelopeByteCount: UInt64
    let reopenedAndAuthenticated: Bool
    let innerValidationComplete: Bool
    let cleanupDisposition: EncryptedEnvelopeCleanupDispositionV1
}

struct EncryptedEnvelopeOpenCryptographicFactsV1: Equatable, Sendable {
    let context: EncryptedEnvelopeOperationReceiptContextV1
    let publicHeader: EncryptedPortableEnvelopePublicHeaderV1
    let authenticatedManifest: EncryptedPortableEnvelopeAuthenticatedManifestV1
    let canonicalHeaderSHA256: Data
    let encryptedFileSHA256: Data
    let plaintextSHA256: Data
    let envelopeByteCount: UInt64
    let outerAuthenticationComplete: Bool
    let innerValidationComplete: Bool
    let cleanupDisposition: EncryptedEnvelopeCleanupDispositionV1
}

struct EncryptedEnvelopeFailureReceiptV1: Codable, Equatable, Hashable, Sendable {
    let operationID: UUID
    let attemptID: UUID
    let failure: EncryptedPortableEnvelopeExternalFailureV1
    let cleanupDisposition: EncryptedEnvelopeCleanupDispositionV1
    let candidateHead: String
    let candidateTree: String
    let toolchainIdentifier: String
    let containsPassphraseOrKeyMaterial: Bool

    init(
        context: EncryptedEnvelopeOperationReceiptContextV1,
        failure: EncryptedPortableEnvelopeExternalFailureV1,
        cleanupDisposition: EncryptedEnvelopeCleanupDispositionV1
    ) throws {
        guard cleanupDisposition == .completed else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        operationID = context.operationID
        attemptID = context.attemptID
        self.failure = failure
        self.cleanupDisposition = cleanupDisposition
        candidateHead = context.candidateHead
        candidateTree = context.candidateTree
        toolchainIdentifier = context.toolchainIdentifier
        containsPassphraseOrKeyMaterial = false
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case operationID, attemptID, failure, cleanupDisposition, candidateHead
        case candidateTree, toolchainIdentifier, containsPassphraseOrKeyMaterial
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let context = try EncryptedEnvelopeOperationReceiptContextV1(
            operationID: c.decode(UUID.self, forKey: .operationID),
            attemptID: c.decode(UUID.self, forKey: .attemptID),
            candidateHead: c.decode(String.self, forKey: .candidateHead),
            candidateTree: c.decode(String.self, forKey: .candidateTree),
            toolchainIdentifier: c.decode(String.self, forKey: .toolchainIdentifier)
        )
        try self.init(
            context: context,
            failure: c.decode(EncryptedPortableEnvelopeExternalFailureV1.self, forKey: .failure),
            cleanupDisposition: c.decode(EncryptedEnvelopeCleanupDispositionV1.self, forKey: .cleanupDisposition)
        )
        guard c.decode(Bool.self, forKey: .containsPassphraseOrKeyMaterial) == false else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
    }
}

struct EncryptedEnvelopeSealReceiptV1: Codable, Equatable, Hashable, Sendable {
    let operationID: UUID
    let attemptID: UUID
    let protocolRelease: EncryptedPortableEnvelopeProtocolReleaseV1
    let kdfProfile: EncryptedEnvelopeKDFProfileV1
    let aeadProfile: EncryptedEnvelopeAEADProfileV1
    let publicEnvelopeID: Data
    let innerKind: EncryptedPortableEnvelopeInnerKindV1
    let innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1
    let reviewProtectionMode: ReviewExchangeProtectionV1?
    let canonicalHeaderSHA256: Data
    let encryptedFileSHA256: Data
    let frameCount: UInt32
    let plaintextByteCount: UInt64
    let ciphertextByteCount: UInt64
    let envelopeByteCount: UInt64
    let neutralFilename: String
    let neutralShareTitle: String
    let sourceProtectionClass: EncryptedEnvelopeProtectionClassV1
    let destinationProtectionClass: EncryptedEnvelopeProtectionClassV1
    let outerValidation: EncryptedEnvelopeValidationResultV1
    let innerValidation: EncryptedEnvelopeValidationResultV1
    let reopenedBeforeShareReady: Bool
    let cleanupDisposition: EncryptedEnvelopeCleanupDispositionV1
    let candidateHead: String
    let candidateTree: String
    let toolchainIdentifier: String
    let deterministicTestResult: EncryptedEnvelopeTestResultV1
    let exportComplianceDisposition: EncryptionExportComplianceDispositionV1
    let errorCategory: EncryptedEnvelopeErrorCategoryV1
    let containsPassphraseOrKeyMaterial: Bool

    private init(
        context: EncryptedEnvelopeOperationReceiptContextV1,
        protocolRelease: EncryptedPortableEnvelopeProtocolReleaseV1 = .current,
        kdfProfile: EncryptedEnvelopeKDFProfileV1 = .released,
        aeadProfile: EncryptedEnvelopeAEADProfileV1 = .released,
        publicEnvelopeID: Data,
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1,
        reviewProtectionMode: ReviewExchangeProtectionV1?,
        canonicalHeaderSHA256: Data,
        encryptedFileSHA256: Data,
        frameCount: UInt32,
        plaintextByteCount: UInt64,
        ciphertextByteCount: UInt64,
        envelopeByteCount: UInt64,
        reopenedBeforeShareReady: Bool,
        cleanupDisposition: EncryptedEnvelopeCleanupDispositionV1 = .completed,
        errorCategory: EncryptedEnvelopeErrorCategoryV1 = .none,
        containsPassphraseOrKeyMaterial: Bool = false
    ) throws {
        try protocolRelease.validateReleased()
        try kdfProfile.validateReleased()
        try aeadProfile.validateReleased()
        try innerProtocolVersion.validateReleased(for: innerKind)
        switch innerKind {
        case .workspaceBackup:
            guard reviewProtectionMode == nil else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
        case .reviewRequest, .reviewResponse:
            guard reviewProtectionMode == .passphraseEncryptedV1 else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
        }
        let (tagTotal, tagOverflow) = UInt64(frameCount).multipliedReportingOverflow(
            by: UInt64(aeadProfile.authenticationTagByteCount)
        )
        let (expectedCiphertext, cipherOverflow) = plaintextByteCount.addingReportingOverflow(tagTotal)
        let (frameHeaderTotal, frameHeaderOverflow) = UInt64(frameCount).multipliedReportingOverflow(
            by: UInt64(protocolRelease.frameHeaderBytes)
        )
        let (framedCiphertext, framedOverflow) = expectedCiphertext.addingReportingOverflow(frameHeaderTotal)
        let (expectedEnvelope, envelopeOverflow) = UInt64(protocolRelease.headerBytes)
            .addingReportingOverflow(framedCiphertext)
        let canonicalFrameCount = try EncryptedPortableEnvelopePublicHeaderV1.canonicalFrameCount(
            plaintextByteCount: plaintextByteCount,
            frameByteLimit: UInt64(aeadProfile.framePlaintextByteLimit)
        )
        guard publicEnvelopeID.count == 16,
              canonicalHeaderSHA256.count == 32,
              encryptedFileSHA256.count == 32,
              frameCount == canonicalFrameCount,
              !tagOverflow, !cipherOverflow, !frameHeaderOverflow, !framedOverflow, !envelopeOverflow,
              ciphertextByteCount == expectedCiphertext,
              envelopeByteCount == expectedEnvelope,
              reopenedBeforeShareReady,
              cleanupDisposition == .completed,
              errorCategory == .none,
              !containsPassphraseOrKeyMaterial else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        operationID = context.operationID
        attemptID = context.attemptID
        self.protocolRelease = protocolRelease
        self.kdfProfile = kdfProfile
        self.aeadProfile = aeadProfile
        self.publicEnvelopeID = publicEnvelopeID
        self.innerKind = innerKind
        self.innerProtocolVersion = innerProtocolVersion
        self.reviewProtectionMode = reviewProtectionMode
        self.canonicalHeaderSHA256 = canonicalHeaderSHA256
        self.encryptedFileSHA256 = encryptedFileSHA256
        self.frameCount = frameCount
        self.plaintextByteCount = plaintextByteCount
        self.ciphertextByteCount = ciphertextByteCount
        self.envelopeByteCount = envelopeByteCount
        neutralFilename = try EncryptedPortableEnvelopeFilenameV1.neutralFileName(
            innerKind: innerKind,
            publicEnvelopeID: publicEnvelopeID
        )
        neutralShareTitle = try EncryptedPortableEnvelopeFilenameV1.neutralShareTitle(
            innerKind: innerKind,
            publicEnvelopeID: publicEnvelopeID
        )
        sourceProtectionClass = context.sourceProtectionClass
        destinationProtectionClass = context.destinationProtectionClass
        outerValidation = .passed
        innerValidation = .passed
        self.reopenedBeforeShareReady = reopenedBeforeShareReady
        self.cleanupDisposition = cleanupDisposition
        candidateHead = context.candidateHead
        candidateTree = context.candidateTree
        toolchainIdentifier = context.toolchainIdentifier
        deterministicTestResult = context.deterministicTestResult
        exportComplianceDisposition = .released
        self.errorCategory = errorCategory
        self.containsPassphraseOrKeyMaterial = containsPassphraseOrKeyMaterial
    }

    init(finalizing facts: EncryptedEnvelopeSealCryptographicFactsV1) throws {
        guard facts.cleanupDisposition == .pending,
              facts.reopenedAndAuthenticated,
              facts.innerValidationComplete,
              facts.authenticatedManifest.publicHeader == facts.publicHeader,
              facts.authenticatedManifest.canonicalHeaderSHA256 == facts.canonicalHeaderSHA256,
              facts.authenticatedManifest.everyFrameAuthenticatesCanonicalHeader else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        try self.init(
            context: facts.context,
            protocolRelease: facts.publicHeader.release,
            kdfProfile: facts.publicHeader.kdfProfile,
            aeadProfile: facts.publicHeader.aeadProfile,
            publicEnvelopeID: facts.publicHeader.publicEnvelopeID,
            innerKind: facts.publicHeader.innerKind,
            innerProtocolVersion: facts.publicHeader.innerProtocolVersion,
            reviewProtectionMode: facts.publicHeader.reviewProtectionMode,
            canonicalHeaderSHA256: facts.canonicalHeaderSHA256,
            encryptedFileSHA256: facts.encryptedFileSHA256,
            frameCount: facts.publicHeader.declaredFrameCount,
            plaintextByteCount: facts.publicHeader.declaredPlaintextByteCount,
            ciphertextByteCount: facts.publicHeader.declaredCiphertextByteCount,
            envelopeByteCount: facts.envelopeByteCount,
            reopenedBeforeShareReady: true,
            cleanupDisposition: .completed
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case operationID, attemptID, protocolRelease, kdfProfile, aeadProfile, publicEnvelopeID
        case innerKind, innerProtocolVersion, reviewProtectionMode, canonicalHeaderSHA256, encryptedFileSHA256
        case frameCount, plaintextByteCount
        case ciphertextByteCount, envelopeByteCount, neutralFilename, sourceProtectionClass
        case neutralShareTitle
        case destinationProtectionClass, outerValidation, innerValidation, reopenedBeforeShareReady
        case cleanupDisposition, candidateHead, candidateTree, toolchainIdentifier
        case deterministicTestResult, exportComplianceDisposition, errorCategory
        case containsPassphraseOrKeyMaterial
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let context = try EncryptedEnvelopeOperationReceiptContextV1(
            operationID: c.decode(UUID.self, forKey: .operationID),
            attemptID: c.decode(UUID.self, forKey: .attemptID),
            sourceProtectionClass: c.decode(EncryptedEnvelopeProtectionClassV1.self, forKey: .sourceProtectionClass),
            destinationProtectionClass: c.decode(EncryptedEnvelopeProtectionClassV1.self, forKey: .destinationProtectionClass),
            candidateHead: c.decode(String.self, forKey: .candidateHead),
            candidateTree: c.decode(String.self, forKey: .candidateTree),
            toolchainIdentifier: c.decode(String.self, forKey: .toolchainIdentifier),
            deterministicTestResult: c.decode(EncryptedEnvelopeTestResultV1.self, forKey: .deterministicTestResult)
        )
        try self.init(
            context: context,
            protocolRelease: c.decode(EncryptedPortableEnvelopeProtocolReleaseV1.self, forKey: .protocolRelease),
            kdfProfile: c.decode(EncryptedEnvelopeKDFProfileV1.self, forKey: .kdfProfile),
            aeadProfile: c.decode(EncryptedEnvelopeAEADProfileV1.self, forKey: .aeadProfile),
            publicEnvelopeID: c.decode(Data.self, forKey: .publicEnvelopeID),
            innerKind: c.decode(EncryptedPortableEnvelopeInnerKindV1.self, forKey: .innerKind),
            innerProtocolVersion: c.decode(EncryptedPortableEnvelopeInnerProtocolVersionV1.self, forKey: .innerProtocolVersion),
            reviewProtectionMode: c.decodeIfPresent(ReviewExchangeProtectionV1.self, forKey: .reviewProtectionMode),
            canonicalHeaderSHA256: c.decode(Data.self, forKey: .canonicalHeaderSHA256),
            encryptedFileSHA256: c.decode(Data.self, forKey: .encryptedFileSHA256),
            frameCount: c.decode(UInt32.self, forKey: .frameCount),
            plaintextByteCount: c.decode(UInt64.self, forKey: .plaintextByteCount),
            ciphertextByteCount: c.decode(UInt64.self, forKey: .ciphertextByteCount),
            envelopeByteCount: c.decode(UInt64.self, forKey: .envelopeByteCount),
            reopenedBeforeShareReady: c.decode(Bool.self, forKey: .reopenedBeforeShareReady),
            cleanupDisposition: c.decode(EncryptedEnvelopeCleanupDispositionV1.self, forKey: .cleanupDisposition),
            errorCategory: c.decode(EncryptedEnvelopeErrorCategoryV1.self, forKey: .errorCategory),
            containsPassphraseOrKeyMaterial: c.decode(Bool.self, forKey: .containsPassphraseOrKeyMaterial)
        )
        guard c.decode(String.self, forKey: .neutralFilename) == neutralFilename,
              c.decode(String.self, forKey: .neutralShareTitle) == neutralShareTitle,
              c.decode(EncryptedEnvelopeValidationResultV1.self, forKey: .outerValidation) == .passed,
              c.decode(EncryptedEnvelopeValidationResultV1.self, forKey: .innerValidation) == .passed,
              c.decode(EncryptionExportComplianceDispositionV1.self, forKey: .exportComplianceDisposition)
                == .released else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
    }
}

struct EncryptedEnvelopeOpenReceiptV1: Codable, Equatable, Hashable, Sendable {
    let operationID: UUID
    let attemptID: UUID
    let protocolRelease: EncryptedPortableEnvelopeProtocolReleaseV1
    let kdfProfile: EncryptedEnvelopeKDFProfileV1
    let aeadProfile: EncryptedEnvelopeAEADProfileV1
    let publicEnvelopeID: Data
    let innerKind: EncryptedPortableEnvelopeInnerKindV1
    let innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1
    let reviewProtectionMode: ReviewExchangeProtectionV1?
    let canonicalHeaderSHA256: Data
    let encryptedFileSHA256: Data
    let frameCount: UInt32
    let authenticatedPlaintextByteCount: UInt64
    let ciphertextByteCount: UInt64
    let envelopeByteCount: UInt64
    let neutralFilename: String
    let neutralShareTitle: String
    let sourceProtectionClass: EncryptedEnvelopeProtectionClassV1
    let destinationProtectionClass: EncryptedEnvelopeProtectionClassV1
    let outerAuthenticationComplete: Bool
    let hostileInnerValidationComplete: Bool
    let cleanupDisposition: EncryptedEnvelopeCleanupDispositionV1
    let candidateHead: String
    let candidateTree: String
    let toolchainIdentifier: String
    let deterministicTestResult: EncryptedEnvelopeTestResultV1
    let exportComplianceDisposition: EncryptionExportComplianceDispositionV1
    let errorCategory: EncryptedEnvelopeErrorCategoryV1
    let containsPassphraseOrKeyMaterial: Bool

    private init(
        context: EncryptedEnvelopeOperationReceiptContextV1,
        protocolRelease: EncryptedPortableEnvelopeProtocolReleaseV1 = .current,
        kdfProfile: EncryptedEnvelopeKDFProfileV1 = .released,
        aeadProfile: EncryptedEnvelopeAEADProfileV1 = .released,
        publicEnvelopeID: Data,
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1,
        reviewProtectionMode: ReviewExchangeProtectionV1?,
        canonicalHeaderSHA256: Data,
        encryptedFileSHA256: Data,
        frameCount: UInt32,
        authenticatedPlaintextByteCount: UInt64,
        ciphertextByteCount: UInt64,
        envelopeByteCount: UInt64,
        outerAuthenticationComplete: Bool,
        hostileInnerValidationComplete: Bool,
        cleanupDisposition: EncryptedEnvelopeCleanupDispositionV1 = .completed,
        errorCategory: EncryptedEnvelopeErrorCategoryV1 = .none,
        containsPassphraseOrKeyMaterial: Bool = false
    ) throws {
        try protocolRelease.validateReleased()
        try kdfProfile.validateReleased()
        try aeadProfile.validateReleased()
        try innerProtocolVersion.validateReleased(for: innerKind)
        switch innerKind {
        case .workspaceBackup:
            guard reviewProtectionMode == nil else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
        case .reviewRequest, .reviewResponse:
            guard reviewProtectionMode == .passphraseEncryptedV1 else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
        }
        let (tagTotal, tagOverflow) = UInt64(frameCount).multipliedReportingOverflow(
            by: UInt64(aeadProfile.authenticationTagByteCount)
        )
        let (expectedCiphertext, cipherOverflow) = authenticatedPlaintextByteCount
            .addingReportingOverflow(tagTotal)
        let (frameHeaderTotal, frameHeaderOverflow) = UInt64(frameCount).multipliedReportingOverflow(
            by: UInt64(protocolRelease.frameHeaderBytes)
        )
        let (framedCiphertext, framedOverflow) = expectedCiphertext.addingReportingOverflow(frameHeaderTotal)
        let (expectedEnvelope, envelopeOverflow) = UInt64(protocolRelease.headerBytes)
            .addingReportingOverflow(framedCiphertext)
        let canonicalFrameCount = try EncryptedPortableEnvelopePublicHeaderV1.canonicalFrameCount(
            plaintextByteCount: authenticatedPlaintextByteCount,
            frameByteLimit: UInt64(aeadProfile.framePlaintextByteLimit)
        )
        guard publicEnvelopeID.count == 16,
              canonicalHeaderSHA256.count == 32,
              encryptedFileSHA256.count == 32,
              frameCount == canonicalFrameCount,
              !tagOverflow, !cipherOverflow, !frameHeaderOverflow, !framedOverflow, !envelopeOverflow,
              ciphertextByteCount == expectedCiphertext,
              envelopeByteCount == expectedEnvelope,
              outerAuthenticationComplete,
              hostileInnerValidationComplete,
              cleanupDisposition == .completed,
              errorCategory == .none,
              !containsPassphraseOrKeyMaterial else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        operationID = context.operationID
        attemptID = context.attemptID
        self.protocolRelease = protocolRelease
        self.kdfProfile = kdfProfile
        self.aeadProfile = aeadProfile
        self.publicEnvelopeID = publicEnvelopeID
        self.innerKind = innerKind
        self.innerProtocolVersion = innerProtocolVersion
        self.reviewProtectionMode = reviewProtectionMode
        self.canonicalHeaderSHA256 = canonicalHeaderSHA256
        self.encryptedFileSHA256 = encryptedFileSHA256
        self.frameCount = frameCount
        self.authenticatedPlaintextByteCount = authenticatedPlaintextByteCount
        self.ciphertextByteCount = ciphertextByteCount
        self.envelopeByteCount = envelopeByteCount
        neutralFilename = try EncryptedPortableEnvelopeFilenameV1.neutralFileName(
            innerKind: innerKind,
            publicEnvelopeID: publicEnvelopeID
        )
        neutralShareTitle = try EncryptedPortableEnvelopeFilenameV1.neutralShareTitle(
            innerKind: innerKind,
            publicEnvelopeID: publicEnvelopeID
        )
        sourceProtectionClass = context.sourceProtectionClass
        destinationProtectionClass = context.destinationProtectionClass
        self.outerAuthenticationComplete = outerAuthenticationComplete
        self.hostileInnerValidationComplete = hostileInnerValidationComplete
        self.cleanupDisposition = cleanupDisposition
        candidateHead = context.candidateHead
        candidateTree = context.candidateTree
        toolchainIdentifier = context.toolchainIdentifier
        deterministicTestResult = context.deterministicTestResult
        exportComplianceDisposition = .released
        self.errorCategory = errorCategory
        self.containsPassphraseOrKeyMaterial = containsPassphraseOrKeyMaterial
    }

    init(finalizing facts: EncryptedEnvelopeOpenCryptographicFactsV1) throws {
        guard facts.cleanupDisposition == .pending,
              facts.outerAuthenticationComplete,
              facts.innerValidationComplete,
              facts.authenticatedManifest.publicHeader == facts.publicHeader,
              facts.authenticatedManifest.canonicalHeaderSHA256 == facts.canonicalHeaderSHA256,
              facts.authenticatedManifest.everyFrameAuthenticatesCanonicalHeader else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        try self.init(
            context: facts.context,
            protocolRelease: facts.publicHeader.release,
            kdfProfile: facts.publicHeader.kdfProfile,
            aeadProfile: facts.publicHeader.aeadProfile,
            publicEnvelopeID: facts.publicHeader.publicEnvelopeID,
            innerKind: facts.publicHeader.innerKind,
            innerProtocolVersion: facts.publicHeader.innerProtocolVersion,
            reviewProtectionMode: facts.publicHeader.reviewProtectionMode,
            canonicalHeaderSHA256: facts.canonicalHeaderSHA256,
            encryptedFileSHA256: facts.encryptedFileSHA256,
            frameCount: facts.publicHeader.declaredFrameCount,
            authenticatedPlaintextByteCount: facts.publicHeader.declaredPlaintextByteCount,
            ciphertextByteCount: facts.publicHeader.declaredCiphertextByteCount,
            envelopeByteCount: facts.envelopeByteCount,
            outerAuthenticationComplete: true,
            hostileInnerValidationComplete: true,
            cleanupDisposition: .completed
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case operationID, attemptID, protocolRelease, kdfProfile, aeadProfile, publicEnvelopeID
        case innerKind, innerProtocolVersion, reviewProtectionMode, canonicalHeaderSHA256, encryptedFileSHA256, frameCount
        case authenticatedPlaintextByteCount, ciphertextByteCount, envelopeByteCount, neutralFilename
        case neutralShareTitle
        case sourceProtectionClass, destinationProtectionClass, outerAuthenticationComplete
        case hostileInnerValidationComplete, cleanupDisposition, candidateHead, candidateTree
        case toolchainIdentifier, deterministicTestResult, exportComplianceDisposition, errorCategory
        case containsPassphraseOrKeyMaterial
    }

    init(from decoder: Decoder) throws {
        try EncryptedEnvelopeStrictDecoderV1.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let context = try EncryptedEnvelopeOperationReceiptContextV1(
            operationID: c.decode(UUID.self, forKey: .operationID),
            attemptID: c.decode(UUID.self, forKey: .attemptID),
            sourceProtectionClass: c.decode(EncryptedEnvelopeProtectionClassV1.self, forKey: .sourceProtectionClass),
            destinationProtectionClass: c.decode(EncryptedEnvelopeProtectionClassV1.self, forKey: .destinationProtectionClass),
            candidateHead: c.decode(String.self, forKey: .candidateHead),
            candidateTree: c.decode(String.self, forKey: .candidateTree),
            toolchainIdentifier: c.decode(String.self, forKey: .toolchainIdentifier),
            deterministicTestResult: c.decode(EncryptedEnvelopeTestResultV1.self, forKey: .deterministicTestResult)
        )
        try self.init(
            context: context,
            protocolRelease: c.decode(EncryptedPortableEnvelopeProtocolReleaseV1.self, forKey: .protocolRelease),
            kdfProfile: c.decode(EncryptedEnvelopeKDFProfileV1.self, forKey: .kdfProfile),
            aeadProfile: c.decode(EncryptedEnvelopeAEADProfileV1.self, forKey: .aeadProfile),
            publicEnvelopeID: c.decode(Data.self, forKey: .publicEnvelopeID),
            innerKind: c.decode(EncryptedPortableEnvelopeInnerKindV1.self, forKey: .innerKind),
            innerProtocolVersion: c.decode(EncryptedPortableEnvelopeInnerProtocolVersionV1.self, forKey: .innerProtocolVersion),
            reviewProtectionMode: c.decodeIfPresent(ReviewExchangeProtectionV1.self, forKey: .reviewProtectionMode),
            canonicalHeaderSHA256: c.decode(Data.self, forKey: .canonicalHeaderSHA256),
            encryptedFileSHA256: c.decode(Data.self, forKey: .encryptedFileSHA256),
            frameCount: c.decode(UInt32.self, forKey: .frameCount),
            authenticatedPlaintextByteCount: c.decode(UInt64.self, forKey: .authenticatedPlaintextByteCount),
            ciphertextByteCount: c.decode(UInt64.self, forKey: .ciphertextByteCount),
            envelopeByteCount: c.decode(UInt64.self, forKey: .envelopeByteCount),
            outerAuthenticationComplete: c.decode(Bool.self, forKey: .outerAuthenticationComplete),
            hostileInnerValidationComplete: c.decode(Bool.self, forKey: .hostileInnerValidationComplete),
            cleanupDisposition: c.decode(EncryptedEnvelopeCleanupDispositionV1.self, forKey: .cleanupDisposition),
            errorCategory: c.decode(EncryptedEnvelopeErrorCategoryV1.self, forKey: .errorCategory),
            containsPassphraseOrKeyMaterial: c.decode(Bool.self, forKey: .containsPassphraseOrKeyMaterial)
        )
        guard c.decode(String.self, forKey: .neutralFilename) == neutralFilename,
              c.decode(String.self, forKey: .neutralShareTitle) == neutralShareTitle,
              c.decode(EncryptionExportComplianceDispositionV1.self, forKey: .exportComplianceDisposition)
                == .released else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
    }
}

private struct EncryptedEnvelopeAnyCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

private enum EncryptedEnvelopeStrictDecoderV1 {
    static func rejectUnknownKeys(_ decoder: Decoder, allowed: [String]) throws {
        let container = try decoder.container(keyedBy: EncryptedEnvelopeAnyCodingKeyV1.self)
        let allowedSet = Set(allowed)
        guard container.allKeys.allSatisfy({ allowedSet.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown or secret-bearing encrypted-envelope receipt field"
            ))
        }
    }
}

enum EncryptionExportComplianceDispositionV1: String, Codable, Hashable, Sendable {
    case classificationAndOwnerReviewRequired = "CLASSIFICATION_AND_OWNER_REVIEW_REQUIRED_NO_EXEMPTION_CLAIM"

    static let released = Self.classificationAndOwnerReviewRequired
    static let declaresExportExemption = false
    static let changesSubmissionOrFilingStatus = false
}

enum ReviewExchangeProtectionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case clearWithExplicitWarning = "CLEAR_WITH_EXPLICIT_WARNING"
    case passphraseEncryptedV1 = "PASSPHRASE_ENCRYPTED_V1"

    static let releasedModes = Set(Self.allCases)
    static let legacyClearReadersRemainAvailable = true
    static let establishesIdentityOrAuthority = false
    static let establishesDeliveryOrLegalEffect = false

    var requiresEncryptedResponseWithSamePassphrase: Bool {
        self == .passphraseEncryptedV1
    }

    var displaysCleartextWarning: Bool {
        self == .clearWithExplicitWarning
    }

    func validateSamePassphraseOwner(
        request: EphemeralPassphraseV1,
        response: EphemeralPassphraseV1
    ) throws {
        guard self == .passphraseEncryptedV1, request === response else {
            throw EncryptedPortableEnvelopeFailureV1.passphraseConfirmationMismatch
        }
    }
}

enum EncryptedPortableEnvelopeClaimsV1 {
    static let providesConfidentiality = true
    static let detectsModification = true
    static let establishesIdentity = false
    static let establishesAuthority = false
    static let establishesDelivery = false
    static let isDigitalSignature = false
    static let providesNonrepudiation = false
    static let isTamperproof = false
    static let establishesExportExemption = false
}

enum EncryptedPortableEnvelopeFilenameV1 {
    static func genericKind(_ innerKind: EncryptedPortableEnvelopeInnerKindV1) -> String {
        switch innerKind {
        case .workspaceBackup: return "Backup"
        case .reviewRequest: return "Review-Request"
        case .reviewResponse: return "Review-Response"
        }
    }

    private static func publicIdentifier(_ publicEnvelopeID: Data) throws -> String {
        guard publicEnvelopeID.count == 16 else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        return publicEnvelopeID.map { String(format: "%02x", $0) }.joined()
    }

    /// Does not incorporate workspace, person, customer, review, backup, or
    /// content. The random public envelope ID provides collision resistance.
    static func neutralFileName(
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        publicEnvelopeID: Data
    ) throws -> String {
        let identifier = try publicIdentifier(publicEnvelopeID)
        return "AssetRounds-\(genericKind(innerKind))-\(identifier).\(EncryptedPortableEnvelopeProtocolReleaseV1.fileExtension)"
    }

    static func neutralShareTitle(
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        publicEnvelopeID: Data
    ) throws -> String {
        "AssetRounds \(genericKind(innerKind)) \(try publicIdentifier(publicEnvelopeID))"
    }
}
