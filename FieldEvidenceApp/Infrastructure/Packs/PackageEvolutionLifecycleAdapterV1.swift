import Foundation
import SwiftData

@MainActor
final class PackageEvolutionLifecycleAdapterV1: PackageEvolutionWritingV1 {
    private let writer: WorkspaceWriterV1
    private let journal: MutationJournalStoreV1
    private let context: ModelContext

    init(writer: WorkspaceWriterV1, journal: MutationJournalStoreV1, modelContext: ModelContext) {
        self.writer = writer; self.journal = journal; context = modelContext
    }

    func activePointer(workspaceID: WorkspaceID, packageID: String) throws -> ActivePackageRegistryPointerV1? {
        let workspace = workspaceID.rawValue
        let packageKey = packageID
        let rows = try context.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.packageID == packageKey }
        ))
        let values = try rows.map { try $0.value() }.sorted { $0.revision < $1.revision }
        guard Set(values.map(\.revision)).count == values.count else { throw PackageEvolutionFailureV1.stalePointer }
        for pair in zip(values, values.dropFirst()) { try pair.1.validateSuccessor(of: pair.0, expectedRevision: pair.0.revision) }
        return values.last
    }

    func acceptedReceipt(mutationID: MutationIDV1) throws -> PackagePromotionReceiptV1? {
        let id = mutationID.rawValue
        let rows = try context.fetch(FetchDescriptor<PackagePromotionReceiptRow>(
            predicate: #Predicate { $0.mutationID == id }
        ))
        guard rows.count <= 1 else { throw PackageEvolutionFailureV1.divergentMutation }
        return try rows.first?.value()
    }

    func acceptedLifecycleClosure(mutationID: MutationIDV1) throws -> PackageEvolutionLifecycleClosureV1? {
        guard let receipt = try acceptedReceipt(mutationID: mutationID) else { return nil }
        let releaseID = receipt.promotedReleaseRecordID
        let runID = receipt.sandboxRunID
        let receiptID = receipt.receiptID
        let releaseRows = try context.fetch(FetchDescriptor<PromotedPackageReleaseRow>(
            predicate: #Predicate { $0.releaseRecordID == releaseID }
        ))
        let runRows = try context.fetch(FetchDescriptor<PackageSandboxRunRow>(
            predicate: #Predicate { $0.runID == runID }
        ))
        let pointerRows = try context.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(
            predicate: #Predicate { $0.promotionReceiptID == receiptID }
        ))
        guard releaseRows.count == 1, runRows.count == 1, pointerRows.count == 1,
              let release = try releaseRows.first?.value(),
              let run = try runRows.first?.value(),
              let resultingPointer = try pointerRows.first?.value() else {
            throw PackageEvolutionFailureV1.divergentMutation
        }
        var pointers = [resultingPointer]
        if let predecessorID = resultingPointer.supersedesPointerID {
            let predecessorRows = try context.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(
                predicate: #Predicate { $0.pointerID == predecessorID }
            ))
            guard predecessorRows.count == 1, let predecessor = try predecessorRows.first?.value() else {
                throw PackageEvolutionFailureV1.divergentMutation
            }
            pointers.append(predecessor)
        }
        return try PackageEvolutionLifecycleClosureV1(
            promotedReleases: [release], sandboxRuns: [run],
            promotionReceipts: [receipt], activePointers: pointers
        )
    }

    func applyPromotion(_ bundle: PackagePromotionAtomicBundleV1) throws -> PackagePromotionReceiptV1 {
        try bundle.validate()
        let expectedRevision = bundle.predecessorPointer?.revision ?? 0
        let mutation = try PackagePromotionMutationV1(
            workspaceID: bundle.resultingPointer.workspaceID,
            expectedPointerRevision: expectedRevision,
            mutationID: bundle.receipt.mutationID,
            bundle: bundle
        )
        _ = try writer.execute(.applyPackagePromotion(mutation), mutationID: mutation.mutationID)
        guard let canonicalReceipt = try journal.receipt(mutationID: mutation.mutationID) else {
            throw PackageEvolutionFailureV1.incompatiblePromotion
        }
        _ = try PackagePromotionMutationReceiptV1(mutation: mutation, mutationReceipt: canonicalReceipt)
        guard let closure = try acceptedLifecycleClosure(mutationID: mutation.mutationID),
              closure.promotedReleases == [bundle.promotedRelease],
              closure.sandboxRuns == [bundle.sandboxRun],
              closure.promotionReceipts == [bundle.receipt],
              closure.activePointers == [bundle.predecessorPointer, bundle.resultingPointer]
                .compactMap({ $0 }).sorted(by: { $0.pointerID.uuidString < $1.pointerID.uuidString }),
              try activePointer(workspaceID: mutation.workspaceID,
                                packageID: mutation.resultingPointer.packageID) == mutation.resultingPointer else {
            throw PackageEvolutionFailureV1.divergentMutation
        }
        return bundle.receipt
    }

    static func validateBackupRestore(_ closure: PackageEvolutionLifecycleClosureV1) throws {
        try closure.validate()
    }

    static func mayDelete(
        release: PromotedPackageReleaseV1,
        activePointers: [ActivePackageRegistryPointerV1],
        frozenPackageReleaseIDs: Set<String>
    ) throws -> Bool {
        try release.validate(); try activePointers.forEach { try $0.validate() }
        return !activePointers.contains(where: { $0.activeReleaseRecordID == release.releaseRecordID })
            && !frozenPackageReleaseIDs.contains(release.packageRelease.packageReleaseID)
    }

    static func searchMetadata(_ receipt: PackagePromotionReceiptV1) -> [String] {
        [receipt.receiptID.uuidString.lowercased(), receipt.promotedReleaseRecordID.uuidString.lowercased(), receipt.semanticDiffSHA256, receipt.exactHead].sorted()
    }
}

enum PackageEvolutionFieldReferenceBoundaryV1 {
    /// Package promotion never rewrites existing work/session bindings.
    static let bindingUpgradePolicy = "EXPLICIT_SUPERSEDING_BINDING_ONLY"
    static let referenceImportTransactionIsSeparate = true
}

extension PackageEvolutionLifecycleAdapterV1 {
    static func validateClientCapabilityClosure(_ closure: ClientCapabilityLifecycleClosureV1) throws {
        try closure.validate()
        guard closure.decision.operation == .upgradeDraft,
              closure.decision.admission == .readWrite else {
            throw ClientCapabilityFailureV1.admissionDenied
        }
    }
}

// MARK: - C26 session lifecycle isolation

extension PackageEvolutionLifecycleAdapterV1 {
    static let surveySessionsRetainPinnedPackageRelease = true
    static let packagePromotionNeverRewritesSurveyHistory = true

    static func validateSurveySessionLifecycle(
        _ session: SurveySessionV1,
        definition: SurveyDefinitionReleaseV1,
        packageRelease: InspectionPackageReleaseV1
    ) throws {
        guard surveySessionsRetainPinnedPackageRelease,
              packagePromotionNeverRewritesSurveyHistory else {
            throw SurveySessionFailureV1.invalidTransition
        }
        try PackageEvolutionCoordinatorV1.validateSurveySessionPin(
            session,
            definition: definition,
            packageRelease: packageRelease
        )
    }
}

// MARK: - C25 survey-definition lifecycle adapter

struct SurveyDefinitionPackageLifecycleMetadataV1: Codable, Equatable, Sendable {
    let definitionID: String
    let releaseID: String
    let releaseRevision: UInt64
    let activityKind: ActivityKindV1
    let lifecycleState: SurveyDefinitionLifecycleStateV1
    let releaseSHA256: String
    let importDisposition: String

    init(
        release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws {
        try release.validate()
        definitionID = release.definitionID.uuidString.lowercased()
        releaseID = release.releaseID.uuidString.lowercased()
        releaseRevision = release.revision
        activityKind = release.activityKind
        self.lifecycleState = lifecycleState
        releaseSHA256 = release.releaseSHA256
        importDisposition = SurveyDefinitionPackageEvolutionConsumerPolicyV1.importDisposition
        try validate()
    }

    func validate() throws {
        guard SurveyDefinitionConsumerPolicyV1.validID(definitionID),
              SurveyDefinitionConsumerPolicyV1.validID(releaseID),
              releaseRevision > 0,
              SurveyDefinitionConsumerPolicyV1.validDigest(releaseSHA256),
              importDisposition == "QUARANTINE_THEN_NEW_DRAFT_IDENTITY" else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
    }
}

extension PackageEvolutionLifecycleAdapterV1 {
    static func surveyDefinitionLifecycleMetadata(
        release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws -> SurveyDefinitionPackageLifecycleMetadataV1 {
        try SurveyDefinitionPackageLifecycleMetadataV1(
            release: release,
            lifecycleState: lifecycleState
        )
    }

    static let surveyDefinitionLifecycleEventsAreCanonical = true
    static let surveyDefinitionImportCreatesNewDraftIdentity = true
    static let surveyDefinitionPreviewIsNonpersistent = true
}
