import Foundation

struct ContentLocatorV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let locatorID: String
    let workspaceID: String
    let contentID: String
    let locatorRevision: Int
    let contentDigest: ContentDigestV1
    let expectedByteLength: Int64

    var id: String { "\(workspaceID)|\(locatorID)" }

    init(
        locatorID: String,
        workspaceID: String,
        contentID: String,
        locatorRevision: Int,
        contentDigest: ContentDigestV1,
        expectedByteLength: Int64
    ) throws {
        guard ContentContractValidationV1.validID(locatorID),
              ContentContractValidationV1.validID(workspaceID),
              ContentContractValidationV1.validID(contentID),
              locatorRevision >= 0, expectedByteLength >= 0 else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.locatorID = locatorID
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.locatorRevision = locatorRevision
        self.contentDigest = contentDigest
        self.expectedByteLength = expectedByteLength
    }

    func validate(against reference: ContentReferenceV1) throws {
        guard workspaceID == reference.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        guard contentID == reference.contentID else { throw ContentContractFailureV1.missingContent }
        guard expectedByteLength == reference.byteLength else { throw ContentContractFailureV1.byteLengthMismatch }
        guard reference.digests.digest(for: contentDigest.algorithm) == contentDigest else {
            throw ContentContractFailureV1.digestMismatch
        }
    }
}

struct ContentManifestEntryV1: Codable, Equatable, Sendable {
    let contentID: String
    let expectedByteLength: Int64
    let mediaType: String
    let digest: ContentDigestV1
    let expectedLocatorRevision: Int
    let requiredForOpen: Bool

    init(
        contentID: String,
        expectedByteLength: Int64,
        mediaType: String,
        digest: ContentDigestV1,
        expectedLocatorRevision: Int,
        requiredForOpen: Bool
    ) throws {
        guard ContentContractValidationV1.validID(contentID), expectedByteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType), expectedLocatorRevision >= 0 else {
            throw ContentContractFailureV1.invalidValue
        }
        self.contentID = contentID
        self.expectedByteLength = expectedByteLength
        self.mediaType = mediaType
        self.digest = digest
        self.expectedLocatorRevision = expectedLocatorRevision
        self.requiredForOpen = requiredForOpen
    }
}

struct ContentManifestV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let manifestID: String
    let workspaceID: String
    let manifestRevision: Int
    let entries: [ContentManifestEntryV1]

    var id: String { "\(workspaceID)|\(manifestID)" }

    init(
        manifestID: String,
        workspaceID: String,
        manifestRevision: Int,
        entries: [ContentManifestEntryV1]
    ) throws {
        guard ContentContractValidationV1.validID(manifestID),
              ContentContractValidationV1.validID(workspaceID), manifestRevision >= 0,
              !entries.isEmpty, entries.count <= ContentContractLimitsV1.maximumManifestEntries,
              entries == entries.sorted(by: { $0.contentID < $1.contentID }),
              Set(entries.map(\.contentID)).count == entries.count else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.manifestID = manifestID
        self.workspaceID = workspaceID
        self.manifestRevision = manifestRevision
        self.entries = entries
    }

    func validate(
        references: [ContentReferenceV1],
        locators: [ContentLocatorV1]
    ) throws {
        guard references.count <= ContentContractLimitsV1.maximumManifestEntries,
              locators.count <= ContentContractLimitsV1.maximumManifestEntries else {
            throw ContentContractFailureV1.limitExceeded
        }
        guard Set(references.map(\.contentID)).count == references.count,
              Set(locators.map(\.contentID)).count == locators.count,
              Set(locators.map { "\($0.workspaceID)|\($0.locatorID)" }).count == locators.count else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        let entryIDs = Set(entries.map(\.contentID))
        guard Set(references.map(\.contentID)) == entryIDs,
              Set(locators.map(\.contentID)) == entryIDs else {
            throw ContentContractFailureV1.missingContent
        }
        for entry in entries {
            let matches = references.filter { $0.contentID == entry.contentID }
            guard matches.count == 1 else { throw ContentContractFailureV1.missingContent }
            let reference = matches[0]
            guard reference.workspaceID == workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
            guard reference.byteLength == entry.expectedByteLength else { throw ContentContractFailureV1.byteLengthMismatch }
            guard reference.mediaType == entry.mediaType else { throw ContentContractFailureV1.mediaTypeMismatch }
            guard reference.digests.digest(for: entry.digest.algorithm) == entry.digest else {
                throw ContentContractFailureV1.digestMismatch
            }
            let locatorMatches = locators.filter { $0.contentID == entry.contentID }
            guard locatorMatches.count == 1 else { throw ContentContractFailureV1.missingContent }
            let locator = locatorMatches[0]
            guard locator.locatorRevision == entry.expectedLocatorRevision else {
                throw ContentContractFailureV1.staleReference
            }
            try locator.validate(against: reference)
        }
    }

    func validateOpenability(
        references: [ContentReferenceV1],
        locators: [ContentLocatorV1]
    ) throws {
        guard references.count <= ContentContractLimitsV1.maximumManifestEntries,
              locators.count <= ContentContractLimitsV1.maximumManifestEntries else {
            throw ContentContractFailureV1.limitExceeded
        }
        guard Set(references.map(\.contentID)).count == references.count,
              Set(locators.map(\.contentID)).count == locators.count,
              Set(locators.map { "\($0.workspaceID)|\($0.locatorID)" }).count == locators.count else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        for entry in entries where entry.requiredForOpen {
            guard let reference = references.first(where: { $0.contentID == entry.contentID }),
                  let locator = locators.first(where: { $0.contentID == entry.contentID }) else {
                throw ContentContractFailureV1.missingContent
            }
            guard reference.workspaceID == workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
            guard reference.byteLength == entry.expectedByteLength else { throw ContentContractFailureV1.byteLengthMismatch }
            guard reference.mediaType == entry.mediaType else { throw ContentContractFailureV1.mediaTypeMismatch }
            guard reference.digests.digest(for: entry.digest.algorithm) == entry.digest else {
                throw ContentContractFailureV1.digestMismatch
            }
            guard locator.locatorRevision == entry.expectedLocatorRevision else {
                throw ContentContractFailureV1.staleReference
            }
            try locator.validate(against: reference)
        }
    }
}

enum ContentManifestCanonicalCodecV1 {
    static func encode(_ value: ContentManifestV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw ContentContractFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> ContentManifestV1 {
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw ContentContractFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(ContentManifestV1.self, from: data)
        guard try encode(value) == data else { throw ContentContractFailureV1.digestMismatch }
        return value
    }
}

extension ContentLocatorV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, locatorID, workspaceID, contentID, locatorRevision
        case contentDigest, expectedByteLength
    }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ContentContractFailureV1.incompatibleVersion }
        try self.init(
            locatorID: c.decode(String.self, forKey: .locatorID), workspaceID: c.decode(String.self, forKey: .workspaceID),
            contentID: c.decode(String.self, forKey: .contentID), locatorRevision: c.decode(Int.self, forKey: .locatorRevision),
            contentDigest: c.decode(ContentDigestV1.self, forKey: .contentDigest), expectedByteLength: c.decode(Int64.self, forKey: .expectedByteLength)
        )
    }
}

extension ContentManifestEntryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case contentID, expectedByteLength, mediaType, digest, expectedLocatorRevision, requiredForOpen }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(contentID: c.decode(String.self, forKey: .contentID), expectedByteLength: c.decode(Int64.self, forKey: .expectedByteLength), mediaType: c.decode(String.self, forKey: .mediaType), digest: c.decode(ContentDigestV1.self, forKey: .digest), expectedLocatorRevision: c.decode(Int.self, forKey: .expectedLocatorRevision), requiredForOpen: c.decode(Bool.self, forKey: .requiredForOpen))
    }
}

extension ContentManifestV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, manifestID, workspaceID, manifestRevision, entries }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ContentContractFailureV1.incompatibleVersion }
        try self.init(manifestID: c.decode(String.self, forKey: .manifestID), workspaceID: c.decode(String.self, forKey: .workspaceID), manifestRevision: c.decode(Int.self, forKey: .manifestRevision), entries: c.decode([ContentManifestEntryV1].self, forKey: .entries))
    }
}
