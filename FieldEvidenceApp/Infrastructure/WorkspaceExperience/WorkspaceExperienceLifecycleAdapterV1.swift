import Foundation
import SwiftData

/// Physical owner of C16's single canonical row. Install commands still pass
/// through WorkspaceWriterV1; this adapter never creates a second writer.
@MainActor
struct WorkspaceExperienceLifecycleAdapterV1 {
    let modelContext: ModelContext
    let workspaceID: WorkspaceID
    private let workspaceWriter: WorkspaceWriterV1?

    init(modelContext: ModelContext, workspaceID: WorkspaceID, workspaceWriter: WorkspaceWriterV1? = nil) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.workspaceWriter = workspaceWriter
    }

    func provenance() throws -> PracticeWorkspaceProvenanceV1? {
        let rows = try modelContext.fetch(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        guard rows.count <= 1 else { throw WorkspaceExperienceFailureV1.duplicateIdentity }
        return try rows.first?.value()
    }

    func classification() throws -> WorkspaceExperienceWorkspaceKindV1 {
        try WorkspaceExperienceClassificationV1.kind(provenance: provenance())
    }

    func replay(_ command: WorkspaceExperienceMutationCommandV1) throws -> WorkspaceExperienceMutationReceiptV1 {
        try command.validateForCanonicalWriter()
        guard command.workspaceID == workspaceID else { throw WorkspaceExperienceFailureV1.wrongWorkspace }
        guard let workspaceWriter else { throw WorkspaceExperienceFailureV1.unsupportedAction }
        if let prior = try workspaceWriter.workspaceExperienceReceipt(for: command) {
            try prior.validate(command: command)
            return prior
        }
        return try workspaceWriter.commitWorkspaceExperience(command)
    }

    /// Clone/fork/configuration reuse creates REAL workspaces. Absence is the
    /// canonical REAL classification, so no destination row is synthesized.
    func validateCloneOrForkDestinationIsReal() throws {
        guard try provenance() == nil else { throw WorkspaceExperienceFailureV1.realWorkspaceRequired }
    }

    func eraseWorkspaceRows() throws {
        for row in try modelContext.fetch(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>())
        where row.workspaceID == workspaceID.rawValue {
            modelContext.delete(row)
        }
    }

    static let replaceRestorePreservesExactProvenance = true
    static let ordinaryEntityDeletePreservesProvenance = true
    static let practiceResetUsesWholeWorkspaceDeletion = true
    static let practiceResetAutomaticallyReinstalls = false
    static let searchProjectionIsRebuildable = true
    static let retentionIsWorkspaceLifetime = true
    static let downgradeRequiresExportOrForwardFix = true
}
