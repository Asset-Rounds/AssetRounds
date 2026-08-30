import CommonCrypto
import CryptoKit
import Foundation
import Security

struct EncryptedPortableEnvelopeStreamingSealResultV1: Equatable, Sendable {
    let publicHeader: EncryptedPortableEnvelopePublicHeaderV1
    let facts: EncryptedEnvelopeSealCryptographicFactsV1
}

struct EncryptedPortableEnvelopeStreamingOpenResultV1: Equatable, Sendable {
    let publicHeader: EncryptedPortableEnvelopePublicHeaderV1
    let facts: EncryptedEnvelopeOpenCryptographicFactsV1
}

enum EncryptedPortableEnvelopeBinaryCodecV1 {
    static func encodePublicHeader(_ value: EncryptedPortableEnvelopePublicHeaderV1) throws -> Data {
        try value.validateReleased()
        var result = Data()
        result.reserveCapacity(EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount)
        result.append(EncryptedPortableEnvelopeProtocolReleaseV1.magic)
        append(value.release.formatVersion, to: &result)
        append(value.release.headerBytes, to: &result)
        result.append(value.innerKind.rawValue)
        result.append(0) // V1 flags are closed and empty.
        append(UInt16(0), to: &result)
        append(value.kdfProfile.profileID, to: &result)
        append(value.aeadProfile.profileID, to: &result)
        append(value.kdfProfile.iterationCount, to: &result)
        result.append(value.kdfProfile.saltByteCount)
        result.append(value.kdfProfile.derivedKeyByteCount)
        result.append(value.aeadProfile.noncePrefixByteCount)
        result.append(value.aeadProfile.authenticationTagByteCount)
        append(value.aeadProfile.framePlaintextByteLimit, to: &result)
        append(value.declaredFrameCount, to: &result)
        append(value.declaredPlaintextByteCount, to: &result)
        append(value.declaredCiphertextByteCount, to: &result)
        result.append(value.publicEnvelopeID)
        result.append(value.salt)
        result.append(value.noncePrefix)
        append(value.innerProtocolVersion.rawValue, to: &result)
        result.append(try reviewProtectionCode(value.reviewProtectionMode))
        result.append(Data(repeating: 0, count: 17))
        guard result.count == EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        return result
    }

    static func decodePublicHeader(_ data: Data) throws -> EncryptedPortableEnvelopePublicHeaderV1 {
        guard data.count == EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        var reader = EncryptedEnvelopeBinaryReaderV1(data)
        guard try reader.readData(count: EncryptedPortableEnvelopeProtocolReleaseV1.magic.count)
                == EncryptedPortableEnvelopeProtocolReleaseV1.magic else {
            throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
        }
        let formatVersion = try reader.readUInt16()
        let headerBytes = try reader.readUInt16()
        guard let kind = EncryptedPortableEnvelopeInnerKindV1(rawValue: try reader.readUInt8()) else {
            throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
        }
        let flags = try reader.readUInt8()
        let reserved = try reader.readUInt16()
        let kdfID = try reader.readUInt16()
        let aeadID = try reader.readUInt16()
        let iterations = try reader.readUInt32()
        let saltBytes = try reader.readUInt8()
        let keyBytes = try reader.readUInt8()
        let noncePrefixBytes = try reader.readUInt8()
        let tagBytes = try reader.readUInt8()
        let frameLimit = try reader.readUInt32()
        let frameCount = try reader.readUInt32()
        let plaintextBytes = try reader.readUInt64()
        let ciphertextBytes = try reader.readUInt64()
        let envelopeID = try reader.readData(count: 16)
        let salt = try reader.readData(count: Int(saltBytes))
        let noncePrefix = try reader.readData(count: Int(noncePrefixBytes))
        let innerProtocolVersion = try EncryptedPortableEnvelopeInnerProtocolVersionV1(
            reader.readUInt16()
        )
        let reviewProtectionMode = try decodeReviewProtection(try reader.readUInt8())
        let remaining = try reader.readData(count: data.count - reader.offset)
        guard flags == 0, reserved == 0, remaining.count == 17,
              remaining.allSatisfy({ $0 == 0 }) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }

        let release = EncryptedPortableEnvelopeProtocolReleaseV1(
            formatVersion: formatVersion,
            headerBytes: headerBytes
        )
        let kdf = EncryptedEnvelopeKDFProfileV1(
            profileID: kdfID,
            iterationCount: iterations,
            saltByteCount: saltBytes,
            derivedKeyByteCount: keyBytes
        )
        let aead = EncryptedEnvelopeAEADProfileV1(
            profileID: aeadID,
            framePlaintextByteLimit: frameLimit,
            authenticationTagByteCount: tagBytes,
            noncePrefixByteCount: noncePrefixBytes
        )
        let result = try EncryptedPortableEnvelopePublicHeaderV1(
            release: release,
            innerKind: kind,
            innerProtocolVersion: innerProtocolVersion,
            reviewProtectionMode: reviewProtectionMode,
            kdfProfile: kdf,
            aeadProfile: aead,
            publicEnvelopeID: envelopeID,
            declaredFrameCount: frameCount,
            declaredPlaintextByteCount: plaintextBytes,
            declaredCiphertextByteCount: ciphertextBytes,
            salt: salt,
            noncePrefix: noncePrefix
        )
        guard try encodePublicHeader(result) == data else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        return result
    }

    static func encodeFrameHeader(_ value: EncryptedEnvelopeFrameHeaderV1) -> Data {
        var result = Data()
        result.reserveCapacity(EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount)
        append(value.index, to: &result)
        result.append(value.isFinal ? EncryptedEnvelopeFrameHeaderV1.finalFlag : 0)
        result.append(contentsOf: [0, 0, 0])
        append(value.ciphertextByteCount, to: &result)
        return result
    }

    static func decodeFrameHeader(_ data: Data) throws -> EncryptedEnvelopeFrameHeaderV1 {
        guard data.count == EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        var reader = EncryptedEnvelopeBinaryReaderV1(data)
        let index = try reader.readUInt32()
        let flags = try reader.readUInt8()
        let reserved = try reader.readData(count: 3)
        let byteCount = try reader.readUInt32()
        guard flags == 0 || flags == EncryptedEnvelopeFrameHeaderV1.finalFlag,
              reserved.allSatisfy({ $0 == 0 }), reader.offset == data.count else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        let value = EncryptedEnvelopeFrameHeaderV1(
            index: index,
            isFinal: flags == EncryptedEnvelopeFrameHeaderV1.finalFlag,
            ciphertextByteCount: byteCount
        )
        guard encodeFrameHeader(value) == data else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        return value
    }

    static func encodeSealedFrame(_ value: EncryptedEnvelopeSealedFrameV1) throws -> Data {
        guard value.authenticationTag.count
                == Int(EncryptedEnvelopeAEADProfileV1.released.authenticationTagByteCount),
              value.ciphertext.count == Int(value.header.ciphertextByteCount) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        var result = encodeFrameHeader(value.header)
        result.append(value.ciphertext)
        result.append(value.authenticationTag)
        return result
    }

    static func decodeSealedFrame(_ data: Data) throws -> EncryptedEnvelopeSealedFrameV1 {
        let headerBytes = EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount
        let tagBytes = Int(EncryptedEnvelopeAEADProfileV1.released.authenticationTagByteCount)
        guard data.count >= headerBytes + tagBytes else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        let header = try decodeFrameHeader(Data(data.prefix(headerBytes)))
        let expected = try EncryptedEnvelopeCheckedArithmeticV1.add(
            headerBytes,
            try EncryptedEnvelopeCheckedArithmeticV1.add(Int(header.ciphertextByteCount), tagBytes)
        )
        guard data.count == expected else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        let ciphertextStart = headerBytes
        let tagStart = ciphertextStart + Int(header.ciphertextByteCount)
        return try EncryptedEnvelopeSealedFrameV1(
            header: header,
            ciphertext: Data(data[ciphertextStart..<tagStart]),
            authenticationTag: Data(data[tagStart..<data.count])
        )
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func reviewProtectionCode(
        _ value: ReviewExchangeProtectionV1?
    ) throws -> UInt8 {
        switch value {
        case nil: return 0
        case .clearWithExplicitWarning: return 1
        case .passphraseEncryptedV1: return 2
        }
    }

    private static func decodeReviewProtection(_ value: UInt8) throws -> ReviewExchangeProtectionV1? {
        switch value {
        case 0: return nil
        case 1: return .clearWithExplicitWarning
        case 2: return .passphraseEncryptedV1
        default: throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
        }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}

struct EncryptedPortableEnvelopeCryptoV1: @unchecked Sendable {
    private let randomBytes: (Int) throws -> Data

    #if DEBUG
    private let keyDerivationObserver: (() -> Void)?
    #endif

    init() {
        randomBytes = Self.systemRandomBytes
        #if DEBUG
        keyDerivationObserver = nil
        #endif
    }

    #if DEBUG
    /// Internal DEBUG-only dependency injection. Release builds contain only
    /// SecRandomCopyBytes and cannot select deterministic envelope entropy.
    init(
        testRandomBytes: @escaping (Int) throws -> Data,
        onKeyDerivation: (() -> Void)? = nil
    ) {
        randomBytes = testRandomBytes
        keyDerivationObserver = onKeyDerivation
    }
    #endif

    func makePublicHeader(
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1,
        reviewProtectionMode: ReviewExchangeProtectionV1?,
        plaintextByteCount: UInt64
    ) throws -> EncryptedPortableEnvelopePublicHeaderV1 {
        let frameCount = try EncryptedPortableEnvelopePublicHeaderV1.canonicalFrameCount(
            plaintextByteCount: plaintextByteCount,
            frameByteLimit: UInt64(EncryptedEnvelopeAEADProfileV1.released.framePlaintextByteLimit)
        )
        let tagTotal = try EncryptedEnvelopeCheckedArithmeticV1.multiply(
            UInt64(frameCount),
            UInt64(EncryptedEnvelopeAEADProfileV1.released.authenticationTagByteCount)
        )
        let ciphertextBytes = try EncryptedEnvelopeCheckedArithmeticV1.add(plaintextByteCount, tagTotal)
        let envelopeID = try checkedRandomBytes(count: 16)
        let salt = try checkedRandomBytes(count: Int(EncryptedEnvelopeKDFProfileV1.released.saltByteCount))
        let noncePrefix = try checkedRandomBytes(
            count: Int(EncryptedEnvelopeAEADProfileV1.released.noncePrefixByteCount)
        )
        return try EncryptedPortableEnvelopePublicHeaderV1(
            innerKind: innerKind,
            innerProtocolVersion: innerProtocolVersion,
            reviewProtectionMode: reviewProtectionMode,
            publicEnvelopeID: envelopeID,
            declaredFrameCount: frameCount,
            declaredPlaintextByteCount: plaintextByteCount,
            declaredCiphertextByteCount: ciphertextBytes,
            salt: salt,
            noncePrefix: noncePrefix
        )
    }

    /// Scans every frame header and resource total without invoking PBKDF2,
    /// allocating plaintext, emitting preview bytes, or writing a destination.
    func structuralPreflight(source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        limits: EncryptedPortableEnvelopeResourceLimitsV1 = .released,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1 = EncryptedEnvelopeNoCancellationV1()
    ) throws -> EncryptedEnvelopeStructuralPreflightReceiptV1 {
        try limits.validate()
        try checkedCancellation(cancellation)
        let envelopeBytes = try source.encryptedEnvelopeByteCount()
        guard envelopeBytes <= limits.maximumEnvelopeByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        guard envelopeBytes >= UInt64(EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        let headerByteCount = EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount
        let publicHeader = try EncryptedPortableEnvelopeBinaryCodecV1.decodePublicHeader(
            try readExactly(source, atOffset: 0, byteCount: headerByteCount)
        )
        try validateResourceAdmission(header: publicHeader, limits: limits)

        var offset = UInt64(headerByteCount)
        var expectedIndex: UInt32 = 0
        var plaintextTotal: UInt64 = 0
        var ciphertextTotal: UInt64 = 0
        var finalCount: UInt32 = 0
        let frameHeaderBytes = EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount
        let tagBytes = Int(publicHeader.aeadProfile.authenticationTagByteCount)

        while expectedIndex < publicHeader.declaredFrameCount {
            try checkedCancellation(cancellation)
            let headerEnd = try EncryptedEnvelopeCheckedArithmeticV1.add(offset, UInt64(frameHeaderBytes))
            guard headerEnd <= envelopeBytes else { throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout }
            let frameHeader = try EncryptedPortableEnvelopeBinaryCodecV1.decodeFrameHeader(
                try readExactly(source, atOffset: offset, byteCount: frameHeaderBytes)
            )
            guard frameHeader.index == expectedIndex else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            try frameHeader.validate(for: publicHeader)
            if frameHeader.isFinal { finalCount += 1 }
            let frameEnd = try EncryptedEnvelopeCheckedArithmeticV1.add(
                headerEnd,
                UInt64(frameHeader.ciphertextByteCount) + UInt64(tagBytes)
            )
            guard frameEnd <= envelopeBytes else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            plaintextTotal = try EncryptedEnvelopeCheckedArithmeticV1.add(
                plaintextTotal,
                UInt64(frameHeader.ciphertextByteCount)
            )
            ciphertextTotal = try EncryptedEnvelopeCheckedArithmeticV1.add(
                ciphertextTotal,
                UInt64(frameHeader.ciphertextByteCount) + UInt64(tagBytes)
            )
            offset = frameEnd
            expectedIndex += 1
        }
        guard offset == envelopeBytes,
              expectedIndex == publicHeader.declaredFrameCount,
              finalCount == 1,
              plaintextTotal == publicHeader.declaredPlaintextByteCount,
              ciphertextTotal == publicHeader.declaredCiphertextByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        return try EncryptedEnvelopeStructuralPreflightReceiptV1(
            protocolIdentifier: publicHeader.release.identifier,
            innerKind: publicHeader.innerKind,
            innerProtocolVersion: publicHeader.innerProtocolVersion,
            reviewProtectionMode: publicHeader.reviewProtectionMode,
            frameCount: expectedIndex,
            plaintextByteCount: plaintextTotal,
            ciphertextByteCount: ciphertextTotal,
            envelopeByteCount: envelopeBytes
        )
    }

    func deriveKey(
        passphrase: EphemeralPassphraseV1,
        header: EncryptedPortableEnvelopePublicHeaderV1,
        limits: EncryptedPortableEnvelopeResourceLimitsV1 = .released
    ) throws -> EphemeralEncryptedEnvelopeKeyV1 {
        try validateResourceAdmission(header: header, limits: limits)
        #if DEBUG
        keyDerivationObserver?()
        #endif
        var keyData = try passphrase.withUnsafeBytes { passphraseBytes in
            guard !passphraseBytes.isEmpty else {
                throw EncryptedPortableEnvelopeFailureV1.invalidPassphrase
            }
            return try Self.pbkdf2SHA256(
                passphraseBytes: passphraseBytes,
                salt: header.salt,
                iterations: header.kdfProfile.iterationCount,
                outputByteCount: Int(header.kdfProfile.derivedKeyByteCount)
            )
        }
        defer { keyData.resetBytes(in: 0..<keyData.count) }
        return try EphemeralEncryptedEnvelopeKeyV1(bytes: keyData)
    }

    private func sealFrame(
        plaintext: Data,
        index: UInt32,
        isFinal: Bool,
        publicHeader: EncryptedPortableEnvelopePublicHeaderV1,
        key: EphemeralEncryptedEnvelopeKeyV1
    ) throws -> EncryptedEnvelopeSealedFrameV1 {
        guard plaintext.count <= Int(publicHeader.aeadProfile.framePlaintextByteLimit) else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        let frameHeader = EncryptedEnvelopeFrameHeaderV1(
            index: index,
            isFinal: isFinal,
            ciphertextByteCount: UInt32(plaintext.count)
        )
        try frameHeader.validate(for: publicHeader)
        let headerData = try EncryptedPortableEnvelopeBinaryCodecV1.encodePublicHeader(publicHeader)
        let frameHeaderData = EncryptedPortableEnvelopeBinaryCodecV1.encodeFrameHeader(frameHeader)
        var authenticatedData = headerData
        authenticatedData.append(frameHeaderData)
        let nonce = try AES.GCM.Nonce(data: nonceData(prefix: publicHeader.noncePrefix, index: index))
        var keyData = key.withUnsafeBytes { Data($0) }
        defer { keyData.resetBytes(in: 0..<keyData.count) }
        do {
            let sealed = try AES.GCM.seal(
                plaintext,
                using: SymmetricKey(data: keyData),
                nonce: nonce,
                authenticating: authenticatedData
            )
            let result = try EncryptedEnvelopeSealedFrameV1(
                header: frameHeader,
                ciphertext: sealed.ciphertext,
                authenticationTag: sealed.tag
            )
            try result.validateBinding(to: publicHeader)
            return result
        } catch {
            throw EncryptedPortableEnvelopeFailureV1.keyDerivationFailed
        }
    }

    private func openFrame(
        _ sealedFrame: EncryptedEnvelopeSealedFrameV1,
        publicHeader: EncryptedPortableEnvelopePublicHeaderV1,
        key: EphemeralEncryptedEnvelopeKeyV1
    ) throws -> Data {
        do {
            try sealedFrame.validateBinding(to: publicHeader)
            let headerData = try EncryptedPortableEnvelopeBinaryCodecV1.encodePublicHeader(publicHeader)
            let frameHeaderData = EncryptedPortableEnvelopeBinaryCodecV1.encodeFrameHeader(sealedFrame.header)
            var authenticatedData = headerData
            authenticatedData.append(frameHeaderData)
            let nonce = try AES.GCM.Nonce(data: nonceData(
                prefix: publicHeader.noncePrefix,
                index: sealedFrame.header.index
            ))
            var keyData = key.withUnsafeBytes { Data($0) }
            defer { keyData.resetBytes(in: 0..<keyData.count) }
            let box = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: sealedFrame.ciphertext,
                tag: sealedFrame.authenticationTag
            )
            return try AES.GCM.open(
                box,
                using: SymmetricKey(data: keyData),
                authenticating: authenticatedData
            )
        } catch {
            // Deliberately do not distinguish a wrong passphrase from any
            // authenticated-header, ciphertext, tag, or nonce damage.
            throw EncryptedPortableEnvelopeFailureV1.wrongPassphraseOrDamagedEnvelope
        }
    }


    func sealStreaming(
        innerSource: any EncryptedEnvelopeBoundedSeekableSourceV1,
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1,
        reviewProtectionMode: ReviewExchangeProtectionV1?,
        passphrase: EphemeralPassphraseV1,
        context: EncryptedEnvelopeOperationReceiptContextV1,
        limits: EncryptedPortableEnvelopeResourceLimitsV1 = .released,
        envelopeScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
        reopenPlaintextScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
        validateSourceInner: EncryptedEnvelopeStreamingInnerValidatorV1,
        validateReopenedInner: EncryptedEnvelopeStreamingInnerValidatorV1,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1 = EncryptedEnvelopeNoCancellationV1()
    ) throws -> EncryptedPortableEnvelopeStreamingSealResultV1 {
        try limits.validate()
        try checkedCancellation(cancellation)
        let plaintextByteCount = try innerSource.encryptedEnvelopeByteCount()
        let plan = try preflightSeal(plaintextByteCount: plaintextByteCount, limits: limits)
        let publicHeader = try makePublicHeader(
            innerKind: innerKind,
            innerProtocolVersion: innerProtocolVersion,
            reviewProtectionMode: reviewProtectionMode,
            plaintextByteCount: plaintextByteCount
        )
        guard plan.frameCount == publicHeader.declaredFrameCount,
              plan.ciphertextByteCount == publicHeader.declaredCiphertextByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        try validateScratch(envelopeScratch, expectedByteCount: plan.envelopeByteCount)
        try validateScratch(reopenPlaintextScratch, expectedByteCount: plaintextByteCount)
        do {
            try validateSourceInner(innerSource, innerKind, innerProtocolVersion)
        } catch {
            throw EncryptedPortableEnvelopeFailureV1.hostileInnerPackage
        }
        try checkedCancellation(cancellation)
        let key = try deriveKey(passphrase: passphrase, header: publicHeader, limits: limits)
        defer { key.clear() }
        try checkedCancellation(cancellation)

        var plaintextHasher = SHA256()
        var envelopeHasher = SHA256()
        let publicHeaderData = try EncryptedPortableEnvelopeBinaryCodecV1.encodePublicHeader(publicHeader)
        let authenticatedManifest = try EncryptedPortableEnvelopeAuthenticatedManifestV1(
            publicHeader: publicHeader,
            canonicalHeaderBytes: publicHeaderData
        )
        do {
            try envelopeScratch.prepareForStreamingWrite(expectedByteCount: plan.envelopeByteCount)
            try envelopeScratch.appendStreamingBytes(publicHeaderData)
            envelopeHasher.update(data: publicHeaderData)
            let frameLimit = UInt64(publicHeader.aeadProfile.framePlaintextByteLimit)
            var plaintextOffset: UInt64 = 0
            var index: UInt32 = 0
            repeat {
                try checkedCancellation(cancellation)
                let remaining = plaintextByteCount - plaintextOffset
                let chunkByteCount = Int(min(frameLimit, remaining))
                let chunk = try readExactly(
                    innerSource,
                    atOffset: plaintextOffset,
                    byteCount: chunkByteCount
                )
                plaintextHasher.update(data: chunk)
                let sealedFrame = try sealFrame(
                    plaintext: chunk,
                    index: index,
                    isFinal: index == publicHeader.declaredFrameCount - 1,
                    publicHeader: publicHeader,
                    key: key
                )
                let encodedFrame = try EncryptedPortableEnvelopeBinaryCodecV1.encodeSealedFrame(sealedFrame)
                try envelopeScratch.appendStreamingBytes(encodedFrame)
                envelopeHasher.update(data: encodedFrame)
                plaintextOffset = try EncryptedEnvelopeCheckedArithmeticV1.add(
                    plaintextOffset,
                    UInt64(chunkByteCount)
                )
                index += 1
            } while index < publicHeader.declaredFrameCount
            guard plaintextOffset == plaintextByteCount,
                  try envelopeScratch.encryptedEnvelopeByteCount() == plan.envelopeByteCount else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            try envelopeScratch.synchronizeStreamingWrite()

            let reopened = try openStreaming(
                envelopeSource: envelopeScratch,
                passphrase: passphrase,
                context: context,
                limits: limits,
                plaintextScratch: reopenPlaintextScratch,
                validateInner: validateReopenedInner,
                cancellation: cancellation
            )
            let plaintextDigest = Data(plaintextHasher.finalize())
            let encryptedFileDigest = Data(envelopeHasher.finalize())
            guard reopened.facts.plaintextSHA256 == plaintextDigest,
                  reopened.facts.encryptedFileSHA256 == encryptedFileDigest,
                  reopened.publicHeader == publicHeader else {
                throw EncryptedPortableEnvelopeFailureV1.wrongPassphraseOrDamagedEnvelope
            }
            let facts = EncryptedEnvelopeSealCryptographicFactsV1(
                context: context,
                publicHeader: publicHeader,
                authenticatedManifest: authenticatedManifest,
                canonicalHeaderSHA256: Data(SHA256.hash(data: publicHeaderData)),
                encryptedFileSHA256: encryptedFileDigest,
                plaintextSHA256: plaintextDigest,
                envelopeByteCount: plan.envelopeByteCount,
                reopenedAndAuthenticated: true,
                innerValidationComplete: true,
                cleanupDisposition: .pending
            )
            return EncryptedPortableEnvelopeStreamingSealResultV1(
                publicHeader: publicHeader,
                facts: facts
            )
        } catch {
            try? envelopeScratch.discardStreamingBytes()
            try? reopenPlaintextScratch.discardStreamingBytes()
            throw error
        }
    }

    func openStreaming(
        envelopeSource: any EncryptedEnvelopeBoundedSeekableSourceV1,
        passphrase: EphemeralPassphraseV1,
        context: EncryptedEnvelopeOperationReceiptContextV1,
        limits: EncryptedPortableEnvelopeResourceLimitsV1 = .released,
        plaintextScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
        validateInner: EncryptedEnvelopeStreamingInnerValidatorV1,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1 = EncryptedEnvelopeNoCancellationV1()
    ) throws -> EncryptedPortableEnvelopeStreamingOpenResultV1 {
        do {
            let preflight = try structuralPreflight(
                source: envelopeSource,
                limits: limits,
                cancellation: cancellation
            )
            let publicHeaderData = try readExactly(
                envelopeSource,
                atOffset: 0,
                byteCount: EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount
            )
            let publicHeader = try EncryptedPortableEnvelopeBinaryCodecV1.decodePublicHeader(publicHeaderData)
            let authenticatedManifest = try EncryptedPortableEnvelopeAuthenticatedManifestV1(
                publicHeader: publicHeader,
                canonicalHeaderBytes: publicHeaderData
            )
            try validateScratch(
                plaintextScratch,
                expectedByteCount: publicHeader.declaredPlaintextByteCount
            )
            try checkedCancellation(cancellation)
            let key = try deriveKey(passphrase: passphrase, header: publicHeader, limits: limits)
            defer { key.clear() }
            try checkedCancellation(cancellation)
            try plaintextScratch.prepareForStreamingWrite(
                expectedByteCount: publicHeader.declaredPlaintextByteCount
            )

            var envelopeHasher = SHA256()
            envelopeHasher.update(data: publicHeaderData)
            var plaintextHasher = SHA256()
            var offset = UInt64(EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount)
            var index: UInt32 = 0
            let frameHeaderByteCount = EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount
            let tagByteCount = Int(publicHeader.aeadProfile.authenticationTagByteCount)
            while index < publicHeader.declaredFrameCount {
                try checkedCancellation(cancellation)
                let frameHeaderData = try readExactly(
                    envelopeSource,
                    atOffset: offset,
                    byteCount: frameHeaderByteCount
                )
                let frameHeader = try EncryptedPortableEnvelopeBinaryCodecV1.decodeFrameHeader(frameHeaderData)
                try frameHeader.validate(for: publicHeader)
                guard frameHeader.index == index else {
                    throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
                }
                let ciphertextOffset = try EncryptedEnvelopeCheckedArithmeticV1.add(
                    offset,
                    UInt64(frameHeaderByteCount)
                )
                let ciphertext = try readExactly(
                    envelopeSource,
                    atOffset: ciphertextOffset,
                    byteCount: Int(frameHeader.ciphertextByteCount)
                )
                let tagOffset = try EncryptedEnvelopeCheckedArithmeticV1.add(
                    ciphertextOffset,
                    UInt64(frameHeader.ciphertextByteCount)
                )
                let tag = try readExactly(
                    envelopeSource,
                    atOffset: tagOffset,
                    byteCount: tagByteCount
                )
                let sealedFrame = try EncryptedEnvelopeSealedFrameV1(
                    header: frameHeader,
                    ciphertext: ciphertext,
                    authenticationTag: tag
                )
                let plaintext = try openFrame(sealedFrame, publicHeader: publicHeader, key: key)
                try plaintextScratch.appendStreamingBytes(plaintext)
                plaintextHasher.update(data: plaintext)
                envelopeHasher.update(data: frameHeaderData)
                envelopeHasher.update(data: ciphertext)
                envelopeHasher.update(data: tag)
                offset = try EncryptedEnvelopeCheckedArithmeticV1.add(
                    tagOffset,
                    UInt64(tagByteCount)
                )
                index += 1
            }
            guard offset == preflight.envelopeByteCount,
                  try plaintextScratch.encryptedEnvelopeByteCount()
                    == publicHeader.declaredPlaintextByteCount else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            try plaintextScratch.synchronizeStreamingWrite()
            do {
                try validateInner(
                    plaintextScratch,
                    publicHeader.innerKind,
                    publicHeader.innerProtocolVersion
                )
            } catch {
                throw EncryptedPortableEnvelopeFailureV1.hostileInnerPackage
            }
            let facts = EncryptedEnvelopeOpenCryptographicFactsV1(
                context: context,
                publicHeader: publicHeader,
                authenticatedManifest: authenticatedManifest,
                canonicalHeaderSHA256: Data(SHA256.hash(data: publicHeaderData)),
                encryptedFileSHA256: Data(envelopeHasher.finalize()),
                plaintextSHA256: Data(plaintextHasher.finalize()),
                envelopeByteCount: preflight.envelopeByteCount,
                outerAuthenticationComplete: true,
                innerValidationComplete: true,
                cleanupDisposition: .pending
            )
            return EncryptedPortableEnvelopeStreamingOpenResultV1(
                publicHeader: publicHeader,
                facts: facts
            )
        } catch {
            try? plaintextScratch.discardStreamingBytes()
            throw Self.mapOpenFailure(error)
        }
    }

    private func preflightSeal(
        plaintextByteCount: UInt64,
        limits: EncryptedPortableEnvelopeResourceLimitsV1
    ) throws -> (frameCount: UInt32, ciphertextByteCount: UInt64, envelopeByteCount: UInt64) {
        try limits.validate()
        guard plaintextByteCount <= limits.maximumPlaintextByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        let frameCount = try EncryptedPortableEnvelopePublicHeaderV1.canonicalFrameCount(
            plaintextByteCount: plaintextByteCount,
            frameByteLimit: UInt64(EncryptedEnvelopeAEADProfileV1.released.framePlaintextByteLimit)
        )
        guard frameCount <= limits.maximumFrameCount else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        let tagTotal = try EncryptedEnvelopeCheckedArithmeticV1.multiply(
            UInt64(frameCount),
            UInt64(EncryptedEnvelopeAEADProfileV1.released.authenticationTagByteCount)
        )
        let ciphertextBytes = try EncryptedEnvelopeCheckedArithmeticV1.add(plaintextByteCount, tagTotal)
        let frameHeaderTotal = try EncryptedEnvelopeCheckedArithmeticV1.multiply(
            UInt64(frameCount),
            UInt64(EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount)
        )
        let envelopeBytes = try EncryptedEnvelopeCheckedArithmeticV1.add(
            UInt64(EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount),
            try EncryptedEnvelopeCheckedArithmeticV1.add(ciphertextBytes, frameHeaderTotal)
        )
        guard envelopeBytes <= limits.maximumEnvelopeByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        return (frameCount, ciphertextBytes, envelopeBytes)
    }

    private func validateResourceAdmission(
        header: EncryptedPortableEnvelopePublicHeaderV1,
        limits: EncryptedPortableEnvelopeResourceLimitsV1
    ) throws {
        try header.validateReleased()
        try limits.validate()
        let frameHeaderBytes = try EncryptedEnvelopeCheckedArithmeticV1.multiply(
            UInt64(header.declaredFrameCount),
            UInt64(header.release.frameHeaderBytes)
        )
        let envelopeBytes = try EncryptedEnvelopeCheckedArithmeticV1.add(
            UInt64(header.release.headerBytes),
            try EncryptedEnvelopeCheckedArithmeticV1.add(
                header.declaredCiphertextByteCount,
                frameHeaderBytes
            )
        )
        guard header.declaredFrameCount <= limits.maximumFrameCount,
              header.declaredPlaintextByteCount <= limits.maximumPlaintextByteCount,
              envelopeBytes <= limits.maximumEnvelopeByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
    }

    private func validateScratch(
        _ scratch: any EncryptedEnvelopeProtectedScratchSinkV1,
        expectedByteCount: UInt64
    ) throws {
        guard scratch.protectionClass == .complete,
              scratch.isExcludedFromBackup,
              expectedByteCount <= EncryptedPortableEnvelopeResourceLimitsV1
                .maximumOperationalScratchByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
    }

    private func readExactly(
        _ source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        atOffset offset: UInt64,
        byteCount: Int
    ) throws -> Data {
        let maximumRead = Int(EncryptedEnvelopeAEADProfileV1.released.framePlaintextByteLimit)
        guard byteCount >= 0, byteCount <= maximumRead else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        let sourceByteCount = try source.encryptedEnvelopeByteCount()
        let end = try EncryptedEnvelopeCheckedArithmeticV1.add(offset, UInt64(byteCount))
        guard end <= sourceByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        let data = try source.readExactly(atOffset: offset, byteCount: byteCount)
        guard data.count == byteCount else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        return data
    }

    private func checkedCancellation(
        _ cancellation: any EncryptedEnvelopeCancellationCheckingV1
    ) throws {
        do {
            try cancellation.checkCancellation()
        } catch {
            throw EncryptedPortableEnvelopeFailureV1.cancelled
        }
    }

    private static func mapOpenFailure(_ error: Error) -> EncryptedPortableEnvelopeExternalFailureV1 {
        if let external = error as? EncryptedPortableEnvelopeExternalFailureV1 { return external }
        guard let failure = error as? EncryptedPortableEnvelopeFailureV1 else {
            return .wrongPassphraseOrDamagedEnvelope
        }
        switch failure {
        case .cancelled:
            return .cancelled
        case .resourceLimitExceeded, .integerOverflow:
            return .resourceLimit
        case .unsupportedProtocol, .unsupportedInnerKind:
            return .unsupportedRelease
        case .invalidPassphrase, .passphraseConfirmationMismatch,
             .invalidPublicHeader, .invalidFrameLayout, .randomGenerationFailed,
             .keyDerivationFailed, .wrongPassphraseOrDamagedEnvelope,
             .hostileInnerPackage:
            return .wrongPassphraseOrDamagedEnvelope
        }
    }

    private func checkedRandomBytes(count: Int) throws -> Data {
        let value = try randomBytes(count)
        guard value.count == count else {
            throw EncryptedPortableEnvelopeFailureV1.randomGenerationFailed
        }
        return value
    }

    private static func systemRandomBytes(_ count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data(repeating: 0, count: count)
        let status = result.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        guard status == errSecSuccess else {
            throw EncryptedPortableEnvelopeFailureV1.randomGenerationFailed
        }
        return result
    }

    private static func pbkdf2SHA256(
        passphraseBytes: UnsafeRawBufferPointer,
        salt: Data,
        iterations: UInt32,
        outputByteCount: Int
    ) throws -> Data {
        guard !passphraseBytes.isEmpty,
              !salt.isEmpty,
              iterations == EncryptedEnvelopeKDFProfileV1.released.iterationCount,
              outputByteCount == Int(EncryptedEnvelopeKDFProfileV1.released.derivedKeyByteCount) else {
            throw EncryptedPortableEnvelopeFailureV1.keyDerivationFailed
        }
        var output = Data(repeating: 0, count: outputByteCount)
        let status: Int32 = output.withUnsafeMutableBytes { outputBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphraseBytes.bindMemory(to: Int8.self).baseAddress,
                    passphraseBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    outputBytes.bindMemory(to: UInt8.self).baseAddress,
                    outputByteCount
                )
            }
        }
        guard status == kCCSuccess else {
            output.resetBytes(in: 0..<output.count)
            throw EncryptedPortableEnvelopeFailureV1.keyDerivationFailed
        }
        return output
    }

    private func nonceData(prefix: Data, index: UInt32) throws -> Data {
        guard prefix.count == Int(EncryptedEnvelopeAEADProfileV1.released.noncePrefixByteCount) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        var result = prefix
        var bigEndian = index.bigEndian
        withUnsafeBytes(of: &bigEndian) { result.append(contentsOf: $0) }
        guard result.count == 12 else {
            throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
        }
        return result
    }
}

#if DEBUG
/// DEBUG-only known-answer surface. It is compiled out of Release and cannot
/// alter production randomness, KDF parameters, or AEAD profiles.
enum EncryptedPortableEnvelopeCryptoTestHooksV1 {
    static let pbkdf2PasswordSalt600000SHA256Hex =
        "669cfe52482116fda1aa2cbe409b2f56c8e4563752b7a28f6eaab614ee005178"
    static let aes256GCMEmptyTagHex = "530f8afbc74536b9a963b4f1c4cb738b"
    static let aes256GCMZeroBlockCiphertextHex = "cea7403d4d606b6e074ec5d3baf39d18"
    static let aes256GCMZeroBlockTagHex = "d0d1c8a799996bf0265b98b5d48ab919"

    static func derivePBKDF2Key(passphraseUTF8: Data, salt: Data) throws -> Data {
        try passphraseUTF8.withUnsafeBytes {
            try EncryptedPortableEnvelopeCryptoV1.pbkdf2SHA256ForTest(
                passphraseBytes: $0,
                salt: salt
            )
        }
    }

    static func sealAES256GCM(
        key: Data,
        nonce: Data,
        plaintext: Data,
        authenticatedData: Data
    ) throws -> (ciphertext: Data, tag: Data) {
        guard key.count == 32, nonce.count == 12 else {
            throw EncryptedPortableEnvelopeFailureV1.keyDerivationFailed
        }
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: AES.GCM.Nonce(data: nonce),
            authenticating: authenticatedData
        )
        return (sealed.ciphertext, sealed.tag)
    }

    static func openAES256GCM(
        key: Data,
        nonce: Data,
        ciphertext: Data,
        tag: Data,
        authenticatedData: Data
    ) throws -> Data {
        guard key.count == 32, nonce.count == 12, tag.count == 16 else {
            throw EncryptedPortableEnvelopeFailureV1.wrongPassphraseOrDamagedEnvelope
        }
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(
                box,
                using: SymmetricKey(data: key),
                authenticating: authenticatedData
            )
        } catch {
            throw EncryptedPortableEnvelopeFailureV1.wrongPassphraseOrDamagedEnvelope
        }
    }
}

private extension EncryptedPortableEnvelopeCryptoV1 {
    static func pbkdf2SHA256ForTest(
        passphraseBytes: UnsafeRawBufferPointer,
        salt: Data
    ) throws -> Data {
        try pbkdf2SHA256(
            passphraseBytes: passphraseBytes,
            salt: salt,
            iterations: EncryptedEnvelopeKDFProfileV1.released.iterationCount,
            outputByteCount: Int(EncryptedEnvelopeKDFProfileV1.released.derivedKeyByteCount)
        )
    }
}
#endif

private struct EncryptedEnvelopeBinaryReaderV1 {
    private let data: Data
    private(set) var offset = 0

    init(_ data: Data) { self.data = data }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try readData(count: 2)
        return bytes.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readData(count: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readData(count: 8)
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0 else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        let end = try EncryptedEnvelopeCheckedArithmeticV1.add(offset, count)
        guard end <= data.count else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        defer { offset = end }
        return Data(data[offset..<end])
    }
}

private enum EncryptedEnvelopeCheckedArithmeticV1 {
    static func add(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, value >= 0 else {
            throw EncryptedPortableEnvelopeFailureV1.integerOverflow
        }
        return value
    }

    static func add(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw EncryptedPortableEnvelopeFailureV1.integerOverflow }
        return value
    }

    static func multiply(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw EncryptedPortableEnvelopeFailureV1.integerOverflow }
        return value
    }
}

extension EncryptedPortableEnvelopeCryptoV1: EncryptedPortableEnvelopeCryptographicPortV1 {}
