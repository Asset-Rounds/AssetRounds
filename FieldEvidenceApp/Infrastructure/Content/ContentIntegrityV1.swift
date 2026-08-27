import Foundation
import CryptoKit

enum ContentIntegrityFailureV1: Error, Equatable, Sendable {
    case wrongWorkspace
    case missingContent
    case staleLocator
    case digestMismatch
    case byteLengthMismatch
    case mediaTypeMismatch
    case immutableOriginal
    case protectedDataUnavailable
    case permissionDenied
    case cancelled
    case insufficientStorage
    case partialEffect
}

struct ContentObservedBytesV1: Equatable, Sendable {
    let workspaceID: String
    let contentID: String
    let byteLength: Int64
    let mediaType: String
    let digests: ContentDigestSetV1

    fileprivate init(
        workspaceID: String,
        contentID: String,
        byteLength: Int64,
        mediaType: String,
        digests: ContentDigestSetV1
    ) throws {
        guard ContentContractValidationV1.validID(workspaceID),
              ContentContractValidationV1.validID(contentID),
              byteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.byteLength = byteLength
        self.mediaType = mediaType
        self.digests = digests
    }
}

struct ContentIntegrityReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: String
    let workspaceID: String
    let contentID: String
    let locatorID: String
    let locatorRevision: Int
    let verifiedDigest: ContentDigestV1
    let verifiedByteLength: Int64
    let verifiedMediaType: String

    init(
        receiptID: String,
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1,
        verifiedDigest: ContentDigestV1
    ) throws {
        guard ContentContractValidationV1.validID(receiptID) else {
            throw ContentContractFailureV1.invalidValue
        }
        try ContentIntegrityV1.verify(reference: reference, locator: locator, observed: observed)
        guard reference.digests.digest(for: verifiedDigest.algorithm) == verifiedDigest else {
            throw ContentIntegrityFailureV1.digestMismatch
        }
        schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        workspaceID = reference.workspaceID
        contentID = reference.contentID
        locatorID = locator.locatorID
        locatorRevision = locator.locatorRevision
        self.verifiedDigest = verifiedDigest
        verifiedByteLength = reference.byteLength
        verifiedMediaType = reference.mediaType
    }

    func validate(
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1
    ) throws {
        try ContentIntegrityV1.verify(reference: reference, locator: locator, observed: observed)
        guard workspaceID == reference.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        guard contentID == reference.contentID else { throw ContentContractFailureV1.missingContent }
        guard locatorID == locator.locatorID,
              locatorRevision == locator.locatorRevision else {
            throw ContentContractFailureV1.staleReference
        }
        guard reference.digests.digest(for: verifiedDigest.algorithm) == verifiedDigest else {
            throw ContentContractFailureV1.digestMismatch
        }
        guard verifiedByteLength == observed.byteLength else { throw ContentContractFailureV1.byteLengthMismatch }
        guard verifiedMediaType == observed.mediaType else { throw ContentContractFailureV1.mediaTypeMismatch }
    }
}

enum ContentIntegrityV1 {
    static func observe(
        workspaceID: String,
        contentID: String,
        data: Data,
        mediaType: String,
        algorithms: [ContentDigestAlgorithmV1] = [.sha256]
    ) throws -> ContentObservedBytesV1 {
        let digests = try algorithms.map { algorithm -> ContentDigestV1 in
            let hexadecimalValue: String
            switch algorithm {
            case .sha256:
                hexadecimalValue = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            case .sha512:
                hexadecimalValue = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
            return try ContentDigestV1(algorithm: algorithm, hexadecimalValue: hexadecimalValue)
        }
        return try ContentObservedBytesV1(
            workspaceID: workspaceID,
            contentID: contentID,
            byteLength: Int64(data.count),
            mediaType: mediaType,
            digests: ContentDigestSetV1(digests)
        )
    }

    static func verify(
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1
    ) throws {
        guard observed.workspaceID == reference.workspaceID,
              locator.workspaceID == reference.workspaceID else {
            throw ContentIntegrityFailureV1.wrongWorkspace
        }
        guard observed.contentID == reference.contentID,
              locator.contentID == reference.contentID else {
            throw ContentIntegrityFailureV1.missingContent
        }
        guard observed.byteLength == reference.byteLength,
              locator.expectedByteLength == reference.byteLength else {
            throw ContentIntegrityFailureV1.byteLengthMismatch
        }
        guard observed.mediaType == reference.mediaType else {
            throw ContentIntegrityFailureV1.mediaTypeMismatch
        }
        try locator.validate(against: reference)
        for digest in reference.digests.values {
            guard observed.digests.digest(for: digest.algorithm) == digest else {
                throw ContentIntegrityFailureV1.digestMismatch
            }
        }
    }

    static func verify(
        manifest: ContentManifestV1,
        references: [ContentReferenceV1],
        locators: [ContentLocatorV1],
        observed: [ContentObservedBytesV1]
    ) throws {
        try manifest.validate(references: references, locators: locators)
        let expected = Set(manifest.entries.map(\.contentID))
        guard Set(observed.map(\.contentID)) == expected,
              observed.count == expected.count else {
            throw ContentIntegrityFailureV1.missingContent
        }
        for entry in manifest.entries {
            guard let reference = references.first(where: { $0.contentID == entry.contentID }),
                  let locator = locators.first(where: { $0.contentID == entry.contentID }),
                  let bytes = observed.first(where: { $0.contentID == entry.contentID }) else {
                throw ContentIntegrityFailureV1.missingContent
            }
            try verify(reference: reference, locator: locator, observed: bytes)
        }
    }
}

extension ContentIntegrityReceiptV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, receiptID, workspaceID, contentID, locatorID, locatorRevision
        case verifiedDigest, verifiedByteLength, verifiedMediaType
    }

    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        let receiptID = try c.decode(String.self, forKey: .receiptID)
        let workspaceID = try c.decode(String.self, forKey: .workspaceID)
        let contentID = try c.decode(String.self, forKey: .contentID)
        let locatorID = try c.decode(String.self, forKey: .locatorID)
        let locatorRevision = try c.decode(Int.self, forKey: .locatorRevision)
        let digest = try c.decode(ContentDigestV1.self, forKey: .verifiedDigest)
        let byteLength = try c.decode(Int64.self, forKey: .verifiedByteLength)
        let mediaType = try c.decode(String.self, forKey: .verifiedMediaType)
        guard [receiptID, workspaceID, contentID, locatorID].allSatisfy(ContentContractValidationV1.validID),
              locatorRevision >= 0, byteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType) else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.locatorID = locatorID
        self.locatorRevision = locatorRevision
        verifiedDigest = digest
        verifiedByteLength = byteLength
        verifiedMediaType = mediaType
    }
}
