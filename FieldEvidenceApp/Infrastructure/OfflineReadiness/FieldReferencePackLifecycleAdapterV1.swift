import Foundation

enum FieldReferenceInterruptionPointV1: String, Codable, Sendable {
    case afterContentReadbackBeforeRelease = "AFTER_CONTENT_READBACK_BEFORE_RELEASE"
    case afterReleaseBeforeReturn = "AFTER_RELEASE_BEFORE_RETURN"
    case afterReadinessBeforeBinding = "AFTER_READINESS_BEFORE_BINDING"
    case afterBindingBeforeReturn = "AFTER_BINDING_BEFORE_RETURN"
}

struct FieldReferencePackLifecycleOperationsV1: Sendable {
    let persist: @Sendable (FieldReferenceImportPlanV1) async throws -> Void
    let validateReadback: @Sendable (FieldReferenceImportPlanV1) async throws -> Void
    let readinessInputs: @Sendable (FieldReferenceReleaseV1, FieldReferenceBindingV1, Date) async throws -> FieldReferenceReadinessInputsV1
    let discardIfUnbound: @Sendable (FieldReferenceImportPlanV1) async throws -> Void
    let acceptedRelease: @Sendable (FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1?
    let appendRelease: @Sendable (FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1
    let acceptedBinding: @Sendable (FieldReferenceBindingV1, FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1?
    let appendBinding: @Sendable (FieldReferenceBindingV1, FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1
    let interruption: @Sendable (FieldReferenceInterruptionPointV1) async throws -> Void

    init(
        persist: @escaping @Sendable (FieldReferenceImportPlanV1) async throws -> Void,
        validateReadback: @escaping @Sendable (FieldReferenceImportPlanV1) async throws -> Void,
        readinessInputs: @escaping @Sendable (FieldReferenceReleaseV1, FieldReferenceBindingV1, Date) async throws -> FieldReferenceReadinessInputsV1,
        discardIfUnbound: @escaping @Sendable (FieldReferenceImportPlanV1) async throws -> Void,
        acceptedRelease: @escaping @Sendable (FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1?,
        appendRelease: @escaping @Sendable (FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1,
        acceptedBinding: @escaping @Sendable (FieldReferenceBindingV1, FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1?,
        appendBinding: @escaping @Sendable (FieldReferenceBindingV1, FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1,
        interruption: @escaping @Sendable (FieldReferenceInterruptionPointV1) async throws -> Void = { _ in }
    ) {
        self.persist = persist
        self.validateReadback = validateReadback
        self.readinessInputs = readinessInputs
        self.discardIfUnbound = discardIfUnbound
        self.acceptedRelease = acceptedRelease
        self.appendRelease = appendRelease
        self.acceptedBinding = acceptedBinding
        self.appendBinding = appendBinding
        self.interruption = interruption
    }
}

/// Provider-free bridge to the existing immutable content authority and sole
/// workspace writer. Content read-back precedes release publication; a crash
/// between them leaves only discardable unbound content, never a binding.
actor FieldReferencePackLifecycleAdapterV1: FieldReferenceContentAuthorityV1, FieldReferencePackWritingV1 {
    private let operations: FieldReferencePackLifecycleOperationsV1
    init(operations: FieldReferencePackLifecycleOperationsV1) { self.operations = operations }

    func persist(_ plan: FieldReferenceImportPlanV1) async throws { try await operations.persist(plan) }
    func validateReadback(_ plan: FieldReferenceImportPlanV1) async throws {
        try await operations.validateReadback(plan)
    }
    func readinessInputs(release: FieldReferenceReleaseV1, binding: FieldReferenceBindingV1, evaluatedAt: Date) async throws -> FieldReferenceReadinessInputsV1 {
        let value = try await operations.readinessInputs(release, binding, evaluatedAt)
        return value
    }
    func discardIfUnbound(_ plan: FieldReferenceImportPlanV1) async throws { try await operations.discardIfUnbound(plan) }
    func acceptedReleaseReceipt(for release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1? { try await operations.acceptedRelease(release) }
    func appendRelease(_ release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1 {
        try await operations.interruption(.afterContentReadbackBeforeRelease)
        let receipt = try await operations.appendRelease(release)
        try await operations.interruption(.afterReleaseBeforeReturn)
        return receipt
    }
    func acceptedBindingReceipt(for binding: FieldReferenceBindingV1, release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1? { try await operations.acceptedBinding(binding, release) }
    func appendBinding(_ binding: FieldReferenceBindingV1, release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1 {
        try await operations.interruption(.afterReadinessBeforeBinding)
        let receipt = try await operations.appendBinding(binding, release)
        try await operations.interruption(.afterBindingBeforeReturn)
        return receipt
    }
}

enum FieldReferenceRetentionV1 {
    static func mayDiscardRelease(_ release: FieldReferenceReleaseV1, bindings: [FieldReferenceBindingV1]) -> Bool {
        !bindings.contains { $0.workspaceID == release.workspaceID && $0.releaseID == release.releaseID }
    }

    static func mayExportBytes(_ release: FieldReferenceReleaseV1) -> Bool {
        release.provenance.licenseScope == .citationAndExportAllowed
    }
}

/// Concrete canonical-row bridge. `WorkspaceWriterV1` remains the only writer;
/// journal lookup supplies idempotent recovery after effect-before-return.
@MainActor
final class WorkspaceWriterFieldReferenceBridgeV1: FieldReferencePackWritingV1 {
    private let writer: WorkspaceWriterV1
    private let journalStore: MutationJournalStoreV1
    init(writer: WorkspaceWriterV1, journalStore: MutationJournalStoreV1) {
        self.writer = writer
        self.journalStore = journalStore
    }

    func acceptedReleaseReceipt(for release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1? {
        try accepted(mutation: .importRelease(release), postImageSHA256: release.releaseSHA256)
    }

    func appendRelease(_ release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1 {
        try commit(.importRelease(release), postImageSHA256: release.releaseSHA256)
    }

    func acceptedBindingReceipt(for binding: FieldReferenceBindingV1, release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1? {
        try binding.validate(release: release)
        return try accepted(mutation: .bind(value: binding, release: release), postImageSHA256: binding.bindingSHA256)
    }

    func appendBinding(_ binding: FieldReferenceBindingV1, release: FieldReferenceReleaseV1) async throws -> FieldReferenceWriteReceiptV1 {
        try commit(.bind(value: binding, release: release), postImageSHA256: binding.bindingSHA256)
    }

    private func accepted(mutation: FieldReferenceMutationV1, postImageSHA256: String) throws -> FieldReferenceWriteReceiptV1? {
        guard let receipt = try journalStore.receipt(mutationID: mutation.mutationID) else { return nil }
        _ = try FieldReferenceMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
        return try FieldReferenceWriteReceiptV1(
            mutationID: mutation.mutationID,
            postImageSHA256: postImageSHA256,
            canonicalMutationReceiptSHA256: receipt.canonicalSHA256()
        )
    }

    private func commit(_ mutation: FieldReferenceMutationV1, postImageSHA256: String) throws -> FieldReferenceWriteReceiptV1 {
        let receipt = try writer.commitFieldReference(mutation)
        _ = try FieldReferenceMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
        return try FieldReferenceWriteReceiptV1(
            mutationID: mutation.mutationID,
            postImageSHA256: postImageSHA256,
            canonicalMutationReceiptSHA256: receipt.canonicalSHA256()
        )
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_OfflineReadiness_FieldReferencePackLifecycleAdapterV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_OfflineReadiness_FieldReferencePackLifecycleAdapterV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
