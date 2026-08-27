import Foundation

enum LocalContentStoreAvailabilityV1: Equatable, Sendable {
    case available(remainingByteCapacity: Int64)
    case protectedDataUnavailable
    case permissionDenied
    case cancelled
}

struct LocalContentStoreEntryV1: Equatable, Sendable {
    let reference: ContentReferenceV1
    let locator: ContentLocatorV1
    let observed: ContentObservedBytesV1
}

struct LocalContentStoreV1: Sendable {
    let workspaceID: String
    private(set) var entries: [String: LocalContentStoreEntryV1]

    init(workspaceID: String) throws {
        guard ContentContractValidationV1.validID(workspaceID) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.workspaceID = workspaceID
        entries = [:]
    }

    mutating func store(
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1,
        availability: LocalContentStoreAvailabilityV1
    ) throws {
        try requireAvailable(availability, byteLength: reference.byteLength)
        guard reference.workspaceID == workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        try ContentIntegrityV1.verify(reference: reference, locator: locator, observed: observed)
        if let current = entries[reference.contentID] {
            try current.reference.validateImmutableIdentity(against: reference)
            guard current.observed == observed else { throw ContentContractFailureV1.immutableOriginal }
            guard locator.locatorRevision == current.locator.locatorRevision,
                  locator == current.locator else { throw ContentContractFailureV1.staleReference }
            return
        }
        guard !entries.values.contains(where: { $0.locator.locatorID == locator.locatorID }) else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        entries[reference.contentID] = LocalContentStoreEntryV1(
            reference: reference,
            locator: locator,
            observed: observed
        )
    }

    mutating func replaceLocator(
        contentID: String,
        expectedLocatorRevision: Int,
        replacement: ContentLocatorV1
    ) throws {
        guard let current = entries[contentID] else { throw ContentContractFailureV1.missingContent }
        guard current.reference.workspaceID == workspaceID,
              replacement.workspaceID == workspaceID else {
            throw ContentContractFailureV1.wrongWorkspace
        }
        guard replacement.contentID == contentID else { throw ContentContractFailureV1.missingContent }
        guard !entries.contains(where: { key, entry in
            key != contentID && entry.locator.locatorID == replacement.locatorID
        }) else { throw ContentContractFailureV1.duplicateIdentity }
        guard current.locator.locatorRevision == expectedLocatorRevision,
              replacement.locatorRevision == expectedLocatorRevision + 1 else {
            throw ContentContractFailureV1.staleReference
        }
        try replacement.validate(against: current.reference)
        entries[contentID] = LocalContentStoreEntryV1(
            reference: current.reference,
            locator: replacement,
            observed: current.observed
        )
    }

    func resolve(_ locator: ContentLocatorV1) throws -> ContentReferenceV1 {
        guard locator.workspaceID == workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        guard let current = entries[locator.contentID] else { throw ContentContractFailureV1.missingContent }
        guard current.locator == locator else { throw ContentContractFailureV1.staleReference }
        try locator.validate(against: current.reference)
        return current.reference
    }

    mutating func deleteRegenerableDerivative(
        contentID: String,
        provenance: ContentDerivativeProvenanceV1
    ) throws {
        guard let current = entries[contentID] else { throw ContentContractFailureV1.missingContent }
        guard current.reference.workspaceID == workspaceID,
              provenance.workspaceID == workspaceID else {
            throw ContentContractFailureV1.wrongWorkspace
        }
        guard current.reference.byteRole == .derivative,
              provenance.derivativeContentID == contentID,
              current.reference.digests.digest(for: provenance.derivativeDigest.algorithm) == provenance.derivativeDigest else {
            throw ContentContractFailureV1.immutableOriginal
        }
        entries.removeValue(forKey: contentID)
    }

    func immutableOriginals() -> [ContentReferenceV1] {
        entries.values.map(\.reference)
            .filter { $0.byteRole == .immutableOriginal }
            .sorted { $0.contentID < $1.contentID }
    }

    private func requireAvailable(
        _ availability: LocalContentStoreAvailabilityV1,
        byteLength: Int64
    ) throws {
        switch availability {
        case .available(let remainingByteCapacity):
            guard remainingByteCapacity >= byteLength else {
                throw ContentIntegrityFailureV1.insufficientStorage
            }
        case .protectedDataUnavailable:
            throw ContentIntegrityFailureV1.protectedDataUnavailable
        case .permissionDenied:
            throw ContentIntegrityFailureV1.permissionDenied
        case .cancelled:
            throw ContentIntegrityFailureV1.cancelled
        }
    }
}

// ContentReferenceV1 intentionally contains no external storage coordinates or
// delivery lifecycle state. Only LocalContentStoreV1 resolves the opaque
// ContentLocatorV1, which cannot change canonical identity.
