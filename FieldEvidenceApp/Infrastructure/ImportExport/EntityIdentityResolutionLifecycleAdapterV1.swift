import Foundation
import SwiftData

/// C13's physical lifecycle boundary.  It reads the three V50 durable
/// families from the incumbent context and delegates every mutation to the
/// one `WorkspaceWriterV1` transaction; plans and previews are never stored.
@MainActor
struct EntityIdentityResolutionLifecycleAdapterV1 {
    static let ordinaryDeletePreservesIdentityHistory = true
    static let wholeWorkspaceEraseUsesExistingRegistry = true

    let modelContext: ModelContext
    let workspaceID: WorkspaceID
    let resolver: any EntityIdentityResolutionCanonicalSourceResolvingV1
    private let workspaceWriter: WorkspaceWriterV1?

    init(
        modelContext: ModelContext,
        workspaceID: WorkspaceID,
        resolver: any EntityIdentityResolutionCanonicalSourceResolvingV1
    ) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.resolver = resolver
        workspaceWriter = nil
    }

    init(
        modelContext: ModelContext,
        workspaceID: WorkspaceID,
        resolver: any EntityIdentityResolutionCanonicalSourceResolvingV1,
        workspaceWriter: WorkspaceWriterV1
    ) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.resolver = resolver
        self.workspaceWriter = workspaceWriter
    }

    func snapshot() throws -> EntityIdentityResolutionBackupSnapshotV1 {
        let value = try physicalSnapshot()
        try validateResolved(value)
        return value
    }

    /// Physical backup deliberately validates hashes, receipt closure, and
    /// successor chains without resolving live source rows.  This permits
    /// offline package validation while activation/query remains fail-closed.
    func backup() throws -> EntityIdentityResolutionBackupSnapshotV1 { try physicalSnapshot() }

    func canonicalExport() throws -> Data {
        try WorkspaceMutationCanonicalV1.data(try backup())
    }

    func decodeSnapshot(_ data: Data) throws -> EntityIdentityResolutionBackupSnapshotV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(EntityIdentityResolutionBackupSnapshotV1.self, from: data)
        guard try WorkspaceMutationCanonicalV1.data(value) == data else {
            throw EntityIdentityResolutionFailureV1.corruptDigest
        }
        try validatePhysical(value)
        return value
    }

    func migrate(snapshotData: Data, fromSchemaVersion: Int) throws -> Data {
        switch fromSchemaVersion {
        case 49:
            return try WorkspaceMutationCanonicalV1.data(EntityIdentityResolutionBackupSnapshotV1(
                workspaceID: workspaceID,
                generationID: try currentGenerationID(),
                aliasLinks: [],
                consolidationReceipts: [],
                mutationReceipts: []
            ))
        case 50:
            return try WorkspaceMutationCanonicalV1.data(try migrate(decodeSnapshot(snapshotData), fromSchemaVersion: fromSchemaVersion))
        default:
            throw EntityIdentityResolutionFailureV1.incompatibleVersion
        }
    }

    func migrate(
        _ value: EntityIdentityResolutionBackupSnapshotV1,
        fromSchemaVersion: Int
    ) throws -> EntityIdentityResolutionBackupSnapshotV1 {
        guard fromSchemaVersion == 50 else { throw EntityIdentityResolutionFailureV1.incompatibleVersion }
        try validatePhysical(value)
        return value
    }

    func replaceRestore(_ value: EntityIdentityResolutionBackupSnapshotV1) throws {
        // Convenience only for callers that have already restored generic
        // mutation history. Package restore must use the proof-map overload.
        let commandList = try commandsFromExistingJournal(for: value)
        guard Set(commandList.map(\.mutationID)).count == commandList.count else {
            throw EntityIdentityResolutionFailureV1.receiptMismatch
        }
        try replaceRestore(value, commands: Dictionary(uniqueKeysWithValues: commandList.map { ($0.mutationID, $0) }))
    }

    /// Generic journal envelopes are the only source of replayable commands.
    /// Restore never synthesizes a command from an immutable effect or receipt.
    func replaceRestore(
        _ value: EntityIdentityResolutionBackupSnapshotV1,
        commands: [MutationIDV1: EntityIdentityResolutionMutationCommandV1]
    ) throws {
        try validatePhysical(value)
        try validateRestoreCommands(commands, for: value)
        try eraseWorkspaceRows()

        // Keep the canonical effect-before-receipt ordering even during
        // replacement: all receipt/command proofs were validated above, but
        // the durable typed receipt is inserted only after its effect row.
        for alias in value.aliasLinks.sorted(by: { $0.linkEventID.uuidString < $1.linkEventID.uuidString }) {
            guard let receipt = value.mutationReceipts.first(where: { $0.mutationID == alias.mutationID }),
                  let command = commands[alias.mutationID] else {
                throw EntityIdentityResolutionFailureV1.receiptMismatch
            }
            let predecessor = alias.supersedesLinkEventID.flatMap { id in value.aliasLinks.first(where: { $0.linkEventID == id }) }
            modelContext.insert(try EntityAliasLinkRowV1(restoring: alias, command: command, receipt: receipt, predecessor: predecessor, resolver: resolver))
            modelContext.insert(try EntityIdentityResolutionMutationReceiptRowV1(restoring: receipt, command: command))
        }
        for consolidation in value.consolidationReceipts.sorted(by: { $0.consolidationReceiptID.uuidString < $1.consolidationReceiptID.uuidString }) {
            guard let receipt = value.mutationReceipts.first(where: { $0.mutationID == consolidation.mutationID }),
                  let command = commands[consolidation.mutationID] else {
                throw EntityIdentityResolutionFailureV1.receiptMismatch
            }
            let predecessor = consolidation.supersedesReceiptID.flatMap { id in value.consolidationReceipts.first(where: { $0.consolidationReceiptID == id }) }
            modelContext.insert(try EntityConsolidationReceiptRowV1(restoring: consolidation, command: command, receipt: receipt, predecessor: predecessor, resolver: resolver))
            modelContext.insert(try EntityIdentityResolutionMutationReceiptRowV1(restoring: receipt, command: command))
        }
    }

    /// Identity event IDs and immutable evidence cannot safely be rebound to a
    /// second workspace.  Incumbent clone/fork therefore accepts only empty
    /// C13 state rather than synthesising a parallel history.
    func clone() throws -> EntityIdentityResolutionBackupSnapshotV1 { try failClosedCrossWorkspaceCopy() }
    func fork() throws -> EntityIdentityResolutionBackupSnapshotV1 { try failClosedCrossWorkspaceCopy() }

    func rebuild(_ query: EntityIdentityResolutionQueryV1) throws -> EntityIdentityResolutionQueryResultV1 {
        try self.query(query)
    }

    func replay(_ command: EntityIdentityResolutionMutationCommandV1) throws -> EntityIdentityResolutionMutationReceiptV1 {
        try command.validate()
        guard command.workspaceID == workspaceID else { throw EntityIdentityResolutionFailureV1.wrongWorkspace }
        try command.validateCanonicalSources(by: resolver)
        guard let workspaceWriter else { throw EntityIdentityResolutionFailureV1.invalidValue }
        if let prior = try workspaceWriter.entityIdentityResolutionReceipt(for: command) {
            try prior.validate(command: command)
            return prior
        }
        let receipt = try workspaceWriter.commitEntityIdentityResolution(command)
        try receipt.validate(command: command)
        return receipt
    }

    func query(_ query: EntityIdentityResolutionQueryV1) throws -> EntityIdentityResolutionQueryResultV1 {
        try query.validate()
        guard query.workspaceID == workspaceID else { throw EntityIdentityResolutionFailureV1.wrongWorkspace }
        guard let workspaceWriter else { throw EntityIdentityResolutionFailureV1.invalidValue }
        let result = try workspaceWriter.entityIdentityResolutionQuery(query)
        try result.validate(for: query)
        return result
    }

    private func failClosedCrossWorkspaceCopy() throws -> EntityIdentityResolutionBackupSnapshotV1 {
        let value = try backup()
        guard value.aliasLinks.isEmpty, value.consolidationReceipts.isEmpty, value.mutationReceipts.isEmpty else {
            throw EntityIdentityResolutionFailureV1.wrongWorkspace
        }
        return value
    }

    private func physicalSnapshot() throws -> EntityIdentityResolutionBackupSnapshotV1 {
        let aliases = try modelContext.fetch(FetchDescriptor<EntityAliasLinkRowV1>()).compactMap { row -> EntityAliasLinkV1? in
            let value = try row.value()
            return value.workspaceID == workspaceID ? value : nil
        }.sorted { $0.linkEventID.uuidString < $1.linkEventID.uuidString }
        let consolidations = try modelContext.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>()).compactMap { row -> EntityConsolidationReceiptV1? in
            let value = try row.value()
            return value.workspaceID == workspaceID ? value : nil
        }.sorted { $0.consolidationReceiptID.uuidString < $1.consolidationReceiptID.uuidString }
        let receipts = try modelContext.fetch(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>()).compactMap { row -> EntityIdentityResolutionMutationReceiptV1? in
            let value = try row.value()
            return value.workspaceID == workspaceID ? value : nil
        }.sorted { $0.mutationID.rawValue.uuidString < $1.mutationID.rawValue.uuidString }
        let value = try EntityIdentityResolutionBackupSnapshotV1(
            workspaceID: workspaceID,
            generationID: try currentGenerationID(receipts: receipts),
            aliasLinks: aliases,
            consolidationReceipts: consolidations,
            mutationReceipts: receipts
        )
        try validatePhysical(value)
        return value
    }

    private func eraseWorkspaceRows() throws {
        for row in try modelContext.fetch(FetchDescriptor<EntityAliasLinkRowV1>()) where row.workspaceID == workspaceID.rawValue { modelContext.delete(row) }
        for row in try modelContext.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>()) where row.workspaceID == workspaceID.rawValue { modelContext.delete(row) }
        for row in try modelContext.fetch(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>()) where row.workspaceID == workspaceID.rawValue { modelContext.delete(row) }
    }

    private func validatePhysical(_ value: EntityIdentityResolutionBackupSnapshotV1) throws {
        try value.validate()
        guard value.workspaceID == workspaceID else { throw EntityIdentityResolutionFailureV1.wrongWorkspace }
        let effects = value.aliasLinks.map(\.mutationID) + value.consolidationReceipts.map(\.mutationID)
        guard Set(effects).count == effects.count,
              Set(effects) == Set(value.mutationReceipts.map(\.mutationID)),
              value.mutationReceipts.allSatisfy({ $0.recoveryState == .receiptCommitted }) else {
            throw EntityIdentityResolutionFailureV1.receiptMismatch
        }
    }

    private func currentGenerationID(
        receipts: [EntityIdentityResolutionMutationReceiptV1] = []
    ) throws -> UUID {
        let receiptGenerationIDs = Set(receipts.map(\.generationID))
        guard receiptGenerationIDs.count <= 1 else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        if let generationID = receiptGenerationIDs.first { return generationID }
        let states = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        guard states.count == 1, let state = states.first else {
            throw EntityIdentityResolutionFailureV1.wrongWorkspace
        }
        return state.generationID
    }

    private func commandsFromExistingJournal(
        for value: EntityIdentityResolutionBackupSnapshotV1
    ) throws -> [EntityIdentityResolutionMutationCommandV1] {
        try validatePhysical(value)
        var commands: [EntityIdentityResolutionMutationCommandV1] = []
        for row in try modelContext.fetch(FetchDescriptor<MutationReceiptRow>()) where row.workspaceID == workspaceID.rawValue {
            let genericReceipt = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            guard case let .applyEntityIdentityResolution(command) = envelope.command else { continue }
            try command.validate()
            guard genericReceipt.mutationID == command.mutationID,
                  genericReceipt.identity.workspaceID == workspaceID,
                  genericReceipt.expectedRevision.generationID == value.generationID else {
                throw EntityIdentityResolutionFailureV1.receiptMismatch
            }
            commands.append(command)
        }
        return commands
    }

    private func validateRestoreCommands(
        _ commands: [MutationIDV1: EntityIdentityResolutionMutationCommandV1],
        for value: EntityIdentityResolutionBackupSnapshotV1
    ) throws {
        let receiptMutationIDs = value.mutationReceipts.map(\.mutationID)
        guard commands.count == receiptMutationIDs.count,
              Set(commands.keys) == Set(receiptMutationIDs),
              commands.allSatisfy({ $0.key == $0.value.mutationID }) else {
            throw EntityIdentityResolutionFailureV1.receiptMismatch
        }
        for command in commands.values {
            try command.validateCanonicalSources(by: resolver)
            guard command.workspaceID == value.workspaceID,
                  command.expectedRevision.generationID == value.generationID,
                  let receipt = value.mutationReceipts.first(where: { $0.mutationID == command.mutationID }) else {
                throw EntityIdentityResolutionFailureV1.receiptMismatch
            }
            try receipt.validate(command: command)
        }
    }

    private func validateResolved(_ value: EntityIdentityResolutionBackupSnapshotV1) throws {
        for alias in value.aliasLinks {
            let predecessor = alias.supersedesLinkEventID.flatMap { id in value.aliasLinks.first(where: { $0.linkEventID == id }) }
            try alias.validateResolved(predecessor: predecessor, resolver: resolver)
        }
        for consolidation in value.consolidationReceipts {
            let predecessor = consolidation.supersedesReceiptID.flatMap { id in value.consolidationReceipts.first(where: { $0.consolidationReceiptID == id }) }
            try consolidation.validateResolved(predecessor: predecessor, resolver: resolver)
        }
    }
}
