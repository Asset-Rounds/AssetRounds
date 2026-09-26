import CoreSpotlight
import CryptoKit
import Foundation
import UniformTypeIdentifiers

final class PrivateSystemDiscoveryFileStateStoreV1: PrivateSystemDiscoveryClientStateStoreV1,
    PrivateSystemDiscoveryGlobalJournalStoreV1, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) throws {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = fileManager
        let directory = self.fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutableDirectory = directory; try mutableDirectory.setResourceValues(values)
    }

    static func applicationSupport(fileManager: FileManager = .default) throws -> Self {
        guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PrivateSystemDiscoveryFailureV1.unavailable
        }
        return try Self(fileURL: root.appendingPathComponent("PrivateSystemDiscovery", isDirectory: true)
            .appendingPathComponent("client-state-v1.json"), fileManager: fileManager)
    }

    func load() throws -> PrivateSystemDiscoveryClientStateV1? {
        try readEnvelope()?.clientState
    }

    func save(_ state: PrivateSystemDiscoveryClientStateV1) throws {
        try state.validate()
        let global = try readEnvelope()?.globalJournal ?? .empty
        try write(.init(schemaVersion: 1, clientState: state, globalJournal: global))
    }

    func clear() throws {
        try save(.empty)
    }

    func loadGlobal() throws -> PrivateSystemDiscoveryGlobalJournalV1? {
        try readEnvelope()?.globalJournal
    }

    func saveGlobal(_ journal: PrivateSystemDiscoveryGlobalJournalV1) throws {
        try journal.validate()
        let state = try readEnvelope()?.clientState ?? .empty
        try write(.init(schemaVersion: 1, clientState: state, globalJournal: journal))
    }

    private func readEnvelope() throws -> PrivateSystemDiscoveryDurableEnvelopeV1? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        if let envelope = try? CompatibilityCanonicalV1.decode(
            PrivateSystemDiscoveryDurableEnvelopeV1.self, from: data
        ) {
            try envelope.validate()
            guard data == (try CompatibilityCanonicalV1.encode(envelope)) else {
                throw PrivateSystemDiscoveryFailureV1.corruptDigest
            }
            return envelope
        }
        let legacy = try CompatibilityCanonicalV1.decode(PrivateSystemDiscoveryClientStateV1.self, from: data)
        try legacy.validate()
        guard data == (try CompatibilityCanonicalV1.encode(legacy)) else {
            throw PrivateSystemDiscoveryFailureV1.corruptDigest
        }
        return .init(schemaVersion: 1, clientState: legacy, globalJournal: .empty)
    }

    private func write(_ envelope: PrivateSystemDiscoveryDurableEnvelopeV1) throws {
        try envelope.validate()
        try CompatibilityCanonicalV1.encode(envelope).write(
            to: fileURL, options: [.atomic, .completeFileProtection]
        )
    }
}

struct PrivateSystemDiscoveryGlobalJournalEntryV1: Codable, Equatable, Sendable {
    let operationID: PrivateSystemDiscoveryOperationIDV1
    let state: PrivateSystemDiscoveryJournalStateV1
    let recordedAt: Date
}

struct PrivateSystemDiscoveryGlobalJournalV1: Codable, Equatable, Sendable {
    static let empty = Self(schemaVersion: 1, entries: [])
    let schemaVersion: Int
    var entries: [PrivateSystemDiscoveryGlobalJournalEntryV1]

    func validate() throws {
        guard schemaVersion == 1, entries.count <= 48 else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        var bindings: [UUID: PrivateSystemDiscoveryOperationIDV1] = [:]
        for entry in entries {
            try entry.operationID.validate()
            guard entry.operationID.operation == .removal else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
            if let prior = bindings[entry.operationID.rawValue], prior != entry.operationID {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
            bindings[entry.operationID.rawValue] = entry.operationID
        }
        for rawID in bindings.keys {
            let states = entries.filter { $0.operationID.rawValue == rawID }.map(\.state)
            guard states == Array([.prepared, .effectApplied, .committed].prefix(states.count)) else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
        }
        let unfinished = bindings.keys.filter { rawID in
            entries.last(where: { $0.operationID.rawValue == rawID })?.state != .committed
        }
        guard unfinished.count <= 1 else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
}

struct PrivateSystemDiscoveryDurableEnvelopeV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let clientState: PrivateSystemDiscoveryClientStateV1
    let globalJournal: PrivateSystemDiscoveryGlobalJournalV1

    func validate() throws {
        guard schemaVersion == 1 else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
        try clientState.validate(); try globalJournal.validate()
    }
}

protocol PrivateSystemDiscoveryGlobalJournalStoreV1: Sendable {
    func loadGlobal() throws -> PrivateSystemDiscoveryGlobalJournalV1?
    func saveGlobal(_ journal: PrivateSystemDiscoveryGlobalJournalV1) throws
}

protocol PrivateSystemDiscoveryContentGuardedIndexClientV1: PrivateSystemDiscoveryProtectedIndexClientV1 {
    func replaceItems(
        deleting identifiers: [String], with items: [PrivateSystemDiscoveryIndexItemV1],
        contentReadToken: AppAccessGateV1.ContentReadToken
    ) async throws
}

final class PrivateSystemDiscoveryCoreSpotlightClientV1: PrivateSystemDiscoveryContentGuardedIndexClientV1, @unchecked Sendable {
    static let indexName = PrivateSystemDiscoveryLifecycleV1.namedIndex
    private let index = CSSearchableIndex(name: PrivateSystemDiscoveryCoreSpotlightClientV1.indexName, protectionClass: .complete)

    func replaceItems(deleting identifiers: [String], with items: [PrivateSystemDiscoveryIndexItemV1]) async throws {
        try await deleteItems(withIdentifiers: identifiers)
        let values = items.map { item -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .data)
            attributes.title = item.titleKey; attributes.contentDescription = item.actionToken
            return CSSearchableItem(uniqueIdentifier: item.uniqueIdentifier,
                domainIdentifier: item.domainIdentifier, attributeSet: attributes)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(values) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func replaceItems(
        deleting identifiers: [String], with items: [PrivateSystemDiscoveryIndexItemV1],
        contentReadToken: AppAccessGateV1.ContentReadToken
    ) async throws {
        try await deleteItems(withIdentifiers: identifiers)
        let values = items.map { item -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .data)
            attributes.title = item.titleKey; attributes.contentDescription = item.actionToken
            return CSSearchableItem(uniqueIdentifier: item.uniqueIdentifier,
                domainIdentifier: item.domainIdentifier, attributeSet: attributes)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try contentReadToken.withContentRead(for: .searchRebuild) {
                    index.indexSearchableItems(values) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
            } catch { continuation.resume(throwing: error) }
        }
    }

    func deleteItems(withIdentifiers identifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func deleteAllItems() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteAllSearchableItems { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}

enum PrivateSystemDiscoveryIndexRuntimeV1 {
    static let shared: PrivateSystemDiscoveryIndexStoreV1 = {
        do { return try PrivateSystemDiscoveryIndexStoreV1() }
        catch { preconditionFailure("Private system discovery protected runtime unavailable: \(error)") }
    }()
}

actor PrivateSystemDiscoveryIndexStoreV1: PrivateSystemDiscoveryIndexLifecyclePortV1 {
    static let indexName = PrivateSystemDiscoveryLifecycleV1.namedIndex
    private let index: any PrivateSystemDiscoveryProtectedIndexClientV1
    private let store: any PrivateSystemDiscoveryClientStateStoreV1
    private let globalStore: any PrivateSystemDiscoveryGlobalJournalStoreV1
    private var value: PrivateSystemDiscoveryClientStateV1
    private var globalJournal: PrivateSystemDiscoveryGlobalJournalV1
    private var mutating = false

    init(indexClient: any PrivateSystemDiscoveryProtectedIndexClientV1,
         clientStateStore: any PrivateSystemDiscoveryClientStateStoreV1) throws {
        guard let globalJournalStore = clientStateStore as? any PrivateSystemDiscoveryGlobalJournalStoreV1 else {
            throw PrivateSystemDiscoveryFailureV1.unavailable
        }
        index = indexClient; store = clientStateStore; globalStore = globalJournalStore
        value = try clientStateStore.load() ?? .empty
        globalJournal = try globalJournalStore.loadGlobal() ?? .empty
        try value.validate(); try globalJournal.validate()
    }

    init(indexClient: any PrivateSystemDiscoveryProtectedIndexClientV1,
         clientStateStore: any PrivateSystemDiscoveryClientStateStoreV1,
         globalJournalStore: any PrivateSystemDiscoveryGlobalJournalStoreV1) throws {
        index = indexClient; store = clientStateStore
        globalStore = globalJournalStore
        value = try clientStateStore.load() ?? .empty
        globalJournal = try globalJournalStore.loadGlobal() ?? .empty
        try value.validate(); try globalJournal.validate()
    }

    init() throws {
        index = PrivateSystemDiscoveryCoreSpotlightClientV1()
        let durableStore = try PrivateSystemDiscoveryFileStateStoreV1.applicationSupport()
        store = durableStore
        globalStore = durableStore
        value = try store.load() ?? .empty
        globalJournal = try globalStore.loadGlobal() ?? .empty
        try value.validate(); try globalJournal.validate()
    }

    func state() async throws -> PrivateSystemDiscoveryStateMapV1 {
        try await serialized { try await recoverGlobal(); try await recover() }; return value.stateMap
    }

    func journalEntries() async throws -> [PrivateSystemDiscoveryJournalEntryV1] {
        try await serialized { try await recoverGlobal(); try await recover() }; return value.journal
    }

    func rebuild(operationID: PrivateSystemDiscoveryOperationIDV1, workspaceID: WorkspaceID,
                 workspaceRevision: UInt64, deletionFrontier: UInt64,
                 descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1],
                 manifest: PrivateSystemDiscoveryManifestV1, optIn: PrivateSystemDiscoveryOptInV1,
                 availability: [AppIntentAvailabilityV1], now: Date) async throws {
        try await serialized {
            try await recoverGlobal(); try await recover(); try operationID.validate(); try manifest.validate(); try optIn.validate()
            try descriptors.forEach { try $0.validate() }; try availability.forEach { try $0.validate() }
            let effectiveOperationID = try currentRebuildOperationID(
                operationID, workspaceID: workspaceID
            )
            guard operationID.operation == .rebuild, operationID.workspaceID == workspaceID,
                  optIn.contains(workspaceID), workspaceRevision >= deletionFrontier,
                  descriptors == descriptors.sorted(by: { $0.stableKey < $1.stableKey }),
                  Set(descriptors.map(\.domain)) == Set(PrivateSystemDiscoveryProjectionDomainV1.allCases),
              availability.count == PrivateSystemDiscoveryActionV1.allCases.count,
                  Set(availability.map(\.action)) == Set(PrivateSystemDiscoveryActionV1.allCases),
                  availability.allSatisfy({ $0.workspaceID == workspaceID && $0.optedIn && $0.available }) else {
                let child = try childOperation(parent: effectiveOperationID, workspaceID: workspaceID,
                    domain: "UNAVAILABLE_REBUILD_REMOVAL_V1")
                if try committed(child, .removal, workspaceID) { return }
                let request = try PrivateSystemDiscoveryRemovalRequestV1(operationRawID: child.rawValue,
                    workspaceID: workspaceID, priorStateSHA256: child.inputSHA256, requestedAt: now)
                try await removePrepared(request); return
            }
            // A completed journal entry is idempotent only when the current
            // enrollment still permits every action and the active derived
            // workspace state is the exact state this request would publish.
            // A prior opt-out removes that state, so it cannot turn a later
            // opt-in of the same canonical source into a no-op.
            if try committed(effectiveOperationID, .rebuild, workspaceID) {
                guard activeWorkspaceIndexMatches(
                    workspaceID: workspaceID,
                    workspaceRevision: workspaceRevision,
                    deletionFrontier: deletionFrontier,
                    descriptors: descriptors
                ) else {
                    throw PrivateSystemDiscoveryFailureV1.unavailable
                }
                return
            }
            let request = try PrivateSystemDiscoveryRebuildRequestV1(operationRawID: effectiveOperationID.rawValue,
                workspaceID: workspaceID, workspaceRevision: workspaceRevision,
                deletionFrontier: deletionFrontier, sourceStateSHA256: operationID.inputSHA256,
                requestedAt: now)
            let payload = PrivateSystemDiscoveryIndexRebuildPayloadV1(request: request,
                descriptors: descriptors, manifest: manifest, optIn: optIn,
                availability: availability, requestedAt: now)
            let workspace = try PrivateSystemDiscoveryWorkspaceStateV1(workspaceID: workspaceID,
                workspaceRevision: workspaceRevision, projections: descriptors,
                deletionFrontier: deletionFrontier, rebuiltAt: now)
            try prepare(effectiveOperationID, resulting: try replacing(workspace), payload: payload,
                logicallyBlock: false, at: now)
            try await recover()
        }
    }

    /// A live caller may mark its pending rebuild as authority-bound. The
    /// token guards durable preparation and the actual Spotlight submission;
    /// callback completion remains an already-admitted pending operation.
    func rebuild(operationID: PrivateSystemDiscoveryOperationIDV1, workspaceID: WorkspaceID,
                 workspaceRevision: UInt64, deletionFrontier: UInt64,
                 descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1],
                 manifest: PrivateSystemDiscoveryManifestV1, optIn: PrivateSystemDiscoveryOptInV1,
                 availability: [AppIntentAvailabilityV1], now: Date,
        contentReadToken: AppAccessGateV1.ContentReadToken) async throws {
        try await serialized {
            // Reject unsupported clients before preparing or replaying any work.
            guard index is any PrivateSystemDiscoveryContentGuardedIndexClientV1 else {
                throw PrivateSystemDiscoveryFailureV1.unavailable
            }
            try contentReadToken.withContentRead(for: .searchRebuild) {}
            // Do not recover a global legacy operation through this guarded route.
            guard globalJournal.entries.isEmpty || globalJournal.entries.last?.state == .committed else {
                throw PrivateSystemDiscoveryFailureV1.unavailable
            }
            try operationID.validate(); try manifest.validate(); try optIn.validate()
            try descriptors.forEach { try $0.validate() }; try availability.forEach { try $0.validate() }
            guard operationID.operation == .rebuild, operationID.workspaceID == workspaceID,
                  workspaceRevision >= deletionFrontier,
                  descriptors == descriptors.sorted(by: { $0.stableKey < $1.stableKey }),
                  Set(descriptors.map(\.domain)) == Set(PrivateSystemDiscoveryProjectionDomainV1.allCases),
                  availability.count == PrivateSystemDiscoveryActionV1.allCases.count,
                  Set(availability.map(\.action)) == Set(PrivateSystemDiscoveryActionV1.allCases),
                  availability.allSatisfy({ $0.workspaceID == workspaceID }) else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
            let effectiveOperationID = try currentRebuildOperationID(
                operationID, workspaceID: workspaceID
            )
            if !optIn.contains(workspaceID)
                || !availability.allSatisfy({ $0.optedIn && $0.available }) {
                // A previously submitted rebuild retains its original owner.
                // Removing a completed enrollment must not replay or discard
                // an uncertain marked operation just to manufacture cleanup.
                guard value.pendingOperation == nil else {
                    throw PrivateSystemDiscoveryFailureV1.unavailable
                }
                if !value.knownWorkspaceIDs.contains(workspaceID),
                   value.stateMap.workspaces.allSatisfy({ $0.workspaceID != workspaceID }) {
                    return
                }
                let child = try childOperation(parent: effectiveOperationID, workspaceID: workspaceID,
                    domain: "UNAVAILABLE_REBUILD_REMOVAL_V1")
                if try committed(child, .removal, workspaceID) { return }
                let map = try PrivateSystemDiscoveryStateMapV1(
                    workspaces: value.stateMap.workspaces.filter { $0.workspaceID != workspaceID })
                try contentReadToken.withContentRead(for: .searchRebuild) {
                    try prepare(child, resulting: map, payload: nil, logicallyBlock: true, at: now)
                }
                try await recover()
                return
            }
            if let pending = value.pendingOperation {
                guard pending.requiresContentAuthority == true,
                      pending.operationID == effectiveOperationID,
                      let payload = pending.rebuild,
                      payload.request.workspaceRevision == workspaceRevision,
                      payload.request.deletionFrontier == deletionFrontier,
                      payload.request.sourceStateSHA256 == effectiveOperationID.inputSHA256,
                      payload.descriptors == descriptors,
                      payload.manifest == manifest,
                      payload.optIn == optIn,
                      availabilitySemanticallyMatches(payload.availability, availability) else {
                    throw PrivateSystemDiscoveryFailureV1.unavailable
                }
                try await recover(contentReadToken: contentReadToken)
                return
            }
            if try committed(effectiveOperationID, .rebuild, workspaceID) {
                guard activeWorkspaceIndexMatches(workspaceID: workspaceID, workspaceRevision: workspaceRevision, deletionFrontier: deletionFrontier, descriptors: descriptors) else { throw PrivateSystemDiscoveryFailureV1.unavailable }
                return
            }
            let request = try PrivateSystemDiscoveryRebuildRequestV1(operationRawID: effectiveOperationID.rawValue,
                workspaceID: workspaceID, workspaceRevision: workspaceRevision,
                deletionFrontier: deletionFrontier, sourceStateSHA256: effectiveOperationID.inputSHA256, requestedAt: now)
            let payload = PrivateSystemDiscoveryIndexRebuildPayloadV1(request: request,
                descriptors: descriptors, manifest: manifest, optIn: optIn, availability: availability, requestedAt: now)
            let workspace = try PrivateSystemDiscoveryWorkspaceStateV1(workspaceID: workspaceID,
                workspaceRevision: workspaceRevision, projections: descriptors,
                deletionFrontier: deletionFrontier, rebuiltAt: now)
            try contentReadToken.withContentRead(for: .searchRebuild) {
                try prepare(effectiveOperationID, resulting: try replacing(workspace), payload: payload,
                    logicallyBlock: false, at: now, requiresContentAuthority: true)
            }
            try await recover(contentReadToken: contentReadToken)
        }
    }

    func remove(operationID: PrivateSystemDiscoveryOperationIDV1,
                workspaceID: WorkspaceID, now: Date) async throws {
        try await serialized {
            try await recoverGlobal(); try await recover(); try operationID.validate()
            guard operationID.operation == .removal, operationID.workspaceID == workspaceID else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
            if try committed(operationID, .removal, workspaceID) { return }
            let request = try PrivateSystemDiscoveryRemovalRequestV1(operationRawID: operationID.rawValue,
                workspaceID: workspaceID, priorStateSHA256: operationID.inputSHA256, requestedAt: now)
            try await removePrepared(request)
        }
    }

    func eraseAll(operationID: PrivateSystemDiscoveryOperationIDV1, now: Date) async throws {
        try await serialized {
            guard value.pendingOperation?.requiresContentAuthority != true else {
                throw PrivateSystemDiscoveryFailureV1.unavailable
            }
            try await recoverGlobal(); try operationID.validate()
            guard operationID.operation == .removal else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
            if try globalCommitted(operationID) { return }
            try beginGlobal(operationID, at: now)
            try await recoverGlobal()
        }
    }

    func dropAndRebuild() async throws {
        try await serialized {
            guard value.pendingOperation?.requiresContentAuthority != true else {
                throw PrivateSystemDiscoveryFailureV1.unavailable
            }
            try await recoverGlobal(); try await index.deleteAllItems(); try store.clear(); value = .empty
        }
    }

#if DEBUG
    /// DEBUG-only test seam: clears this process-wide store's durable client
    /// state and global journal so each test starts from an empty journal.
    /// Production never calls it; operation identities stay fail-closed.
    func resetDurableStateForTestingV1() async throws {
        try await serialized {
            try store.save(.empty); try globalStore.saveGlobal(.empty)
            value = .empty; globalJournal = .empty
        }
    }
#endif

    private func serialized<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        guard !mutating else { throw PrivateSystemDiscoveryFailureV1.unavailable }
        mutating = true; defer { mutating = false }; return try await body()
    }

    private func removePrepared(_ request: PrivateSystemDiscoveryRemovalRequestV1) async throws {
        try request.validate()
        let map = try PrivateSystemDiscoveryStateMapV1(
            workspaces: value.stateMap.workspaces.filter { $0.workspaceID != request.workspaceID })
        try prepare(request.operationID, resulting: map, payload: nil,
            logicallyBlock: true, at: request.requestedAt)
        try await recover()
    }

    private func prepare(_ operationID: PrivateSystemDiscoveryOperationIDV1,
                         resulting: PrivateSystemDiscoveryStateMapV1,
                         payload: PrivateSystemDiscoveryIndexRebuildPayloadV1?,
                         logicallyBlock: Bool, at: Date,
                         requiresContentAuthority: Bool? = nil) throws {
        guard value.pendingOperation == nil else { throw PrivateSystemDiscoveryFailureV1.unavailable }
        let prior = operationID.inputSHA256; let result = try digest(resulting)
        let pending = PrivateSystemDiscoveryPendingOperationV1(operationID: operationID,
            operation: operationID.operation, workspaceID: operationID.workspaceID,
            expectedPriorStateSHA256: prior, resultingStateSHA256: result,
            rebuild: payload, preparedAt: at, requiresContentAuthority: requiresContentAuthority)
        let entry = try PrivateSystemDiscoveryJournalEntryV1(operationID: operationID,
            expectedPriorStateSHA256: prior, resultingStateSHA256: nil,
            state: .prepared, recordedAt: at)
        var known = Set(value.knownWorkspaceIDs); known.insert(operationID.workspaceID)
        var inventory = Dictionary(uniqueKeysWithValues: value.workspaceInventory.map {
            ($0.workspaceID, $0.deletionFrontier)
        })
        if let payload { inventory[operationID.workspaceID] = payload.request.deletionFrontier }
        else if inventory[operationID.workspaceID] == nil { inventory[operationID.workspaceID] = 0 }
        let sortedInventory = inventory.map {
            PrivateSystemDiscoveryWorkspaceInventoryV1(workspaceID: $0.key, deletionFrontier: $0.value)
        }.sorted { $0.workspaceID.rawValue.uuidString < $1.workspaceID.rawValue.uuidString }
        let candidate = try PrivateSystemDiscoveryClientStateV1(
            stateMap: logicallyBlock ? resulting : value.stateMap,
            knownWorkspaceIDs: known.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString },
            workspaceInventory: sortedInventory,
            journal: value.journal + [entry], pendingOperation: pending)
        try store.save(candidate)
        value = candidate
    }

    private func recover(
        contentReadToken: AppAccessGateV1.ContentReadToken? = nil
    ) async throws {
        guard let pending = value.pendingOperation else { return }
        if pending.requiresContentAuthority == true, contentReadToken == nil {
            throw PrivateSystemDiscoveryFailureV1.unavailable
        }
        let entries = value.journal.filter { $0.operationID == pending.operationID.rawValue }
        if entries.last?.state == .prepared {
            var candidate = value
            switch pending.operation {
            case .rebuild:
                guard let payload = pending.rebuild else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
                try payload.request.validate(); try payload.manifest.validate(); try payload.optIn.validate()
                let workspace = try PrivateSystemDiscoveryWorkspaceStateV1(
                    workspaceID: pending.workspaceID,
                    workspaceRevision: payload.request.workspaceRevision,
                    projections: payload.descriptors,
                    deletionFrontier: payload.request.deletionFrontier,
                    rebuiltAt: payload.requestedAt)
                if let contentReadToken {
                    guard let guarded = index as? any PrivateSystemDiscoveryContentGuardedIndexClientV1 else {
                        throw PrivateSystemDiscoveryFailureV1.unavailable
                    }
                    try await guarded.replaceItems(deleting: identifiers(pending.workspaceID),
                        with: payload.manifest.actions.map { item(pending.workspaceID, $0) },
                        contentReadToken: contentReadToken)
                } else {
                    try await index.replaceItems(deleting: identifiers(pending.workspaceID),
                        with: payload.manifest.actions.map { item(pending.workspaceID, $0) })
                }
                candidate.stateMap = try replacing(workspace)
            case .removal:
                try await index.deleteItems(withIdentifiers: identifiers(pending.workspaceID))
            }
            guard try digest(candidate.stateMap) == pending.resultingStateSHA256 else {
                throw PrivateSystemDiscoveryFailureV1.corruptDigest
            }
            candidate.journal.append(try transition(pending, .effectApplied))
            if let contentReadToken, pending.requiresContentAuthority == true {
                try contentReadToken.withContentRead(for: .searchRebuild) {
                    try candidate.validate(); try store.save(candidate); value = candidate
                }
            } else {
                try candidate.validate(); try store.save(candidate); value = candidate
            }
        }
        guard value.journal.last(where: { $0.operationID == pending.operationID.rawValue })?.state == .effectApplied else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        var candidate = value
        candidate.journal.append(try transition(pending, .committed))
        if pending.operation == .removal {
            candidate.knownWorkspaceIDs.removeAll { $0 == pending.workspaceID }
            candidate.workspaceInventory.removeAll { $0.workspaceID == pending.workspaceID }
        }
        candidate.pendingOperation = nil
        if let contentReadToken, pending.requiresContentAuthority == true {
            try contentReadToken.withContentRead(for: .searchRebuild) {
                try candidate.validate(); try store.save(candidate); value = candidate
            }
        } else {
            try candidate.validate(); try store.save(candidate); value = candidate
        }
    }

    private func beginGlobal(_ operationID: PrivateSystemDiscoveryOperationIDV1, at: Date) throws {
        guard globalJournal.entries.isEmpty || globalJournal.entries.last?.state == .committed else {
            throw PrivateSystemDiscoveryFailureV1.unavailable
        }
        var candidate = trimmingGlobalJournalForNewOperation(globalJournal)
        candidate.entries.append(.init(operationID: operationID, state: .prepared, recordedAt: at))
        try candidate.validate()
        try globalStore.saveGlobal(candidate)
        globalJournal = candidate
    }

    private func recoverGlobal() async throws {
        guard let pending = globalJournal.entries.last,
              pending.state != .committed else { return }
        let operationID = pending.operationID
        try operationID.validate()
        if pending.state == .prepared {
            try await recover()
            for workspaceID in value.knownWorkspaceIDs {
                let child = try childOperation(parent: operationID, workspaceID: workspaceID,
                    domain: "GLOBAL_ERASE_REMOVAL_V1")
                if try !committed(child, .removal, workspaceID) {
                    let request = try PrivateSystemDiscoveryRemovalRequestV1(operationRawID: child.rawValue,
                        workspaceID: workspaceID, priorStateSHA256: child.inputSHA256,
                        requestedAt: pending.recordedAt)
                    try await removePrepared(request)
                }
            }
            try await index.deleteAllItems()
            var candidate = globalJournal
            candidate.entries.append(.init(operationID: operationID,
                state: .effectApplied, recordedAt: pending.recordedAt))
            try candidate.validate()
            try globalStore.saveGlobal(candidate)
            globalJournal = candidate
        }
        guard globalJournal.entries.last?.operationID == operationID,
              globalJournal.entries.last?.state == .effectApplied else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        try store.clear()
        value = .empty
        var candidate = globalJournal
        candidate.entries.append(.init(operationID: operationID,
            state: .committed, recordedAt: pending.recordedAt))
        candidate = trimmingGlobalJournalAfterCommit(candidate)
        try candidate.validate()
        try globalStore.saveGlobal(candidate)
        globalJournal = candidate
    }

    private func globalCommitted(_ operationID: PrivateSystemDiscoveryOperationIDV1) throws -> Bool {
        let entries = globalJournal.entries.filter { $0.operationID.rawValue == operationID.rawValue }
        guard entries.isEmpty || entries.allSatisfy({ $0.operationID == operationID }) else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        return entries.last?.state == .committed
    }

    private func trimmingGlobalJournalForNewOperation(
        _ journal: PrivateSystemDiscoveryGlobalJournalV1
    ) -> PrivateSystemDiscoveryGlobalJournalV1 {
        var candidate = journal
        let completedRawIDs = candidate.entries.filter { $0.state == .committed }
            .map { $0.operationID.rawValue }
        if completedRawIDs.count >= 16, let oldest = completedRawIDs.first {
            candidate.entries.removeAll { $0.operationID.rawValue == oldest }
        }
        return candidate
    }

    private func trimmingGlobalJournalAfterCommit(
        _ journal: PrivateSystemDiscoveryGlobalJournalV1
    ) -> PrivateSystemDiscoveryGlobalJournalV1 {
        var candidate = journal
        let completedRawIDs = candidate.entries.filter { $0.state == .committed }
            .map { $0.operationID.rawValue }
        for rawID in completedRawIDs.dropLast(16) {
            candidate.entries.removeAll { $0.operationID.rawValue == rawID }
        }
        return candidate
    }

    private func transition(_ pending: PrivateSystemDiscoveryPendingOperationV1,
                            _ state: PrivateSystemDiscoveryJournalStateV1) throws -> PrivateSystemDiscoveryJournalEntryV1 {
        try .init(operationID: pending.operationID,
            expectedPriorStateSHA256: pending.expectedPriorStateSHA256,
            resultingStateSHA256: pending.resultingStateSHA256,
            state: state, recordedAt: pending.preparedAt)
    }

    private func committed(_ operationID: PrivateSystemDiscoveryOperationIDV1,
                           _ operation: PrivateSystemDiscoveryJournalOperationV1,
                           _ workspaceID: WorkspaceID) throws -> Bool {
        let entries = value.journal.filter { $0.operationID == operationID.rawValue }
        guard entries.isEmpty || entries.allSatisfy({
            $0.operation == operation
                && $0.workspaceID == workspaceID
                && $0.expectedPriorStateSHA256 == operationID.inputSHA256
        }) else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        if let pending = value.pendingOperation, pending.operationID.rawValue == operationID.rawValue,
           pending.operationID != operationID { throw PrivateSystemDiscoveryFailureV1.invalidValue }
        return entries.last?.state == .committed
    }

    private func replacing(_ workspace: PrivateSystemDiscoveryWorkspaceStateV1) throws -> PrivateSystemDiscoveryStateMapV1 {
        try .init(workspaces: (value.stateMap.workspaces.filter { $0.workspaceID != workspace.workspaceID } + [workspace])
            .sorted { $0.workspaceID.rawValue.uuidString < $1.workspaceID.rawValue.uuidString })
    }

    private func activeWorkspaceIndexMatches(
        workspaceID: WorkspaceID,
        workspaceRevision: UInt64,
        deletionFrontier: UInt64,
        descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1]
    ) -> Bool {
        value.stateMap.workspaces.first(where: { $0.workspaceID == workspaceID }).map {
            $0.workspaceRevision == workspaceRevision
                && $0.deletionFrontier == deletionFrontier
                && $0.projections == descriptors
        } ?? false
    }

    private func availabilitySemanticallyMatches(
        _ left: [AppIntentAvailabilityV1], _ right: [AppIntentAvailabilityV1]
    ) -> Bool {
        guard left.count == right.count else { return false }
        let keys: (AppIntentAvailabilityV1) -> String = {
            "\($0.action.rawValue)|\($0.workspaceID.rawValue.uuidString)|\($0.optedIn)|\($0.featureReason.rawValue)|\($0.appAccessPermitsContent)|\($0.protectedDataAvailable)|\($0.available)"
        }
        return left.map(keys).sorted() == right.map(keys).sorted()
    }

    /// A removal after this operation's commit starts a new enrollment. Keep
    /// that identity even once its effectApplied state becomes active, so a
    /// cold retry can finish the same pending operation without resubmission.
    private func currentRebuildOperationID(
        _ operationID: PrivateSystemDiscoveryOperationIDV1,
        workspaceID: WorkspaceID
    ) throws -> PrivateSystemDiscoveryOperationIDV1 {
        guard operationID.operation == .rebuild,
              try committed(operationID, .rebuild, workspaceID),
              let originalCommit = value.journal.lastIndex(where: {
                  $0.operationID == operationID.rawValue && $0.state == .committed
              }),
              let removalIndex = value.journal.lastIndex(where: {
                  $0.operation == .removal && $0.workspaceID == workspaceID
                      && $0.state == .committed
              }), removalIndex > originalCommit else { return operationID }
        let removal = value.journal[removalIndex]
        guard let removalPriorStateSHA256 = removal.expectedPriorStateSHA256 else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        let removalOperationID = try PrivateSystemDiscoveryOperationIDV1(
            rawValue: removal.operationID,
            operation: removal.operation,
            workspaceID: removal.workspaceID,
            inputSHA256: removalPriorStateSHA256
        )
        let digest = CompatibilityCanonicalV1.sha256(Data(
            ("PRIVATE_SYSTEM_DISCOVERY_REENROLL_V1|" + operationID.bindingSHA256
                + "|" + removalOperationID.bindingSHA256).utf8
        ))
        let compact = String(digest.prefix(32))
        let text = "\(compact.prefix(8))-\(compact.dropFirst(8).prefix(4))-\(compact.dropFirst(12).prefix(4))-\(compact.dropFirst(16).prefix(4))-\(compact.dropFirst(20).prefix(12))"
        guard let rawValue = UUID(uuidString: text) else {
            throw PrivateSystemDiscoveryFailureV1.corruptDigest
        }
        let rebound = try PrivateSystemDiscoveryOperationIDV1(rawValue: rawValue, operation: .rebuild,
            workspaceID: workspaceID, inputSHA256: operationID.inputSHA256)
        // An unrelated newer enrollment may already own the active workspace.
        // Only this rebound's pending/committed lineage can resume over it;
        // the caller still checks that its exact source state matches.
        if value.stateMap.workspaces.contains(where: { $0.workspaceID == workspaceID }),
           value.pendingOperation?.operationID != rebound,
           try !committed(rebound, .rebuild, workspaceID) {
            throw PrivateSystemDiscoveryFailureV1.unavailable
        }
        return rebound
    }

    private func identifiers(_ workspaceID: WorkspaceID) -> [String] {
        PrivateSystemDiscoveryActionV1.allCases.map { identifier(workspaceID, $0) }
    }
    private func identifier(_ workspaceID: WorkspaceID, _ action: PrivateSystemDiscoveryActionV1) -> String {
        "private-system-discovery|\(workspaceID.rawValue.uuidString.lowercased())|\(action.rawValue)"
    }
    private func domain(_ workspaceID: WorkspaceID) -> String {
        "private-system-discovery|\(workspaceID.rawValue.uuidString.lowercased())"
    }
    private func item(_ workspaceID: WorkspaceID,
                      _ action: PrivateSystemDiscoveryActionDescriptorV1) -> PrivateSystemDiscoveryIndexItemV1 {
        .init(uniqueIdentifier: identifier(workspaceID, action.action), domainIdentifier: domain(workspaceID),
            titleKey: action.titleKey, actionToken: action.action.rawValue)
    }
    private func digest(_ map: PrivateSystemDiscoveryStateMapV1) throws -> String {
        CompatibilityCanonicalV1.sha256(try CompatibilityCanonicalV1.encode(map))
    }
    private func childOperation(parent: PrivateSystemDiscoveryOperationIDV1,
                                workspaceID: WorkspaceID,
                                domain: String) throws -> PrivateSystemDiscoveryOperationIDV1 {
        let basis = domain + "|" + parent.bindingSHA256 + "|" + workspaceID.rawValue.uuidString.lowercased()
        let digestBytes = Array(SHA256.hash(data: Data(basis.utf8)))
        let input = digestBytes.map { String(format: "%02x", $0) }.joined()
        let bytes = Array(SHA256.hash(data: Data((domain + "|UUID|" + parent.bindingSHA256 + "|" + workspaceID.rawValue.uuidString.lowercased()).utf8)).prefix(16))
        let id = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
            bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        return try .init(rawValue: id, operation: .removal, workspaceID: workspaceID, inputSHA256: input)
    }
}
