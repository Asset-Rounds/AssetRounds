import Foundation
import SwiftData
import UIKit

enum ProductionFieldReferenceLifecycleFailureV1: Error, Equatable {
    case sessionChanged
    case sourcesChanged
    case protectedDataUnavailable
    case clockChanged
    case cleanupDeferred
}

/// Current-session composition of the existing C23 coordinator, byte owner
/// and writer. Each call creates its own access and source observation.
@MainActor
final class ProductionFieldReferencePackLifecycleV1 {
    private weak var session: StoreSessionCoordinator?
    private weak var originalWriter: WorkspaceWriterV1?
    private let workspaceID: WorkspaceID
    private let generationID: UUID
    private let uiGenerationToken: UInt64
    private let accessGate: AppAccessGateV1
    private let clock: any ApplicationClock
    private let ledger: OwnedStorageLedgerV1
    private let applicationSupportURL: URL
    #if DEBUG
    var interruptionForTesting: (@Sendable (FieldReferenceInterruptionPointV1) async throws -> Void)?
    #endif

    init(session: StoreSessionCoordinator, accessGate: AppAccessGateV1,
         clock: any ApplicationClock, ownedStorageLedger: OwnedStorageLedgerV1,
         expectedApplicationSupportURL: URL) {
        self.session = session; originalWriter = session.workspaceWriter
        workspaceID = session.workspaceID; generationID = session.generationID
        uiGenerationToken = session.uiGenerationToken; self.accessGate = accessGate
        self.clock = clock; ledger = ownedStorageLedger
        applicationSupportURL = expectedApplicationSupportURL
    }

    func importRelease(_ plan: FieldReferenceImportPlanV1) async throws -> FieldReferenceWriteReceiptV1 {
        let operation = try await begin(workspaceID: plan.release.workspaceID)
        defer { operation.releaseReservation() }
        let receipt = try await operation.coordinator().importRelease(plan)
        try await operation.validate()
        return receipt
    }

    func bind(_ binding: FieldReferenceBindingV1, to release: FieldReferenceReleaseV1) async throws
        -> FieldReferenceWriteReceiptV1 {
        let operation = try await begin(workspaceID: binding.workspaceID)
        let receipt = try await operation.coordinator().bind(binding, to: release)
        try await operation.validate()
        return receipt
    }

    func discardIfUnbound(_ plan: FieldReferenceImportPlanV1) async throws {
        let operation = try await begin(workspaceID: plan.release.workspaceID)
        try await operation.discardIfUnbound(plan)
    }

    private func begin(workspaceID: WorkspaceID) async throws -> Operation {
        let token = try await accessGate.beginContentRead(for: .bulkImport)
        try Task.checkCancellation()
        guard workspaceID == self.workspaceID else { throw FieldReferencePackFailureV1.wrongWorkspace }
        guard let session, let originalWriter, originalWriter === session.workspaceWriter,
              session.workspaceID == workspaceID, session.generationID == generationID,
              session.uiGenerationToken == uiGenerationToken else {
            throw ProductionFieldReferenceLifecycleFailureV1.sessionChanged
        }
        let interruption: @Sendable (FieldReferenceInterruptionPointV1) async throws -> Void
        #if DEBUG
        interruption = interruptionForTesting ?? { _ in }
        #else
        interruption = { _ in }
        #endif
        return try Operation(session: session, token: token, accessGate: accessGate,
            clock: clock, ledger: ledger, applicationSupportURL: applicationSupportURL,
            interruption: interruption)
    }

    @MainActor private final class Operation {
        private let session: StoreSessionCoordinator
        private let writer: WorkspaceWriterV1
        private let workspaceID: WorkspaceID
        private let generationID: UUID
        private let uiGenerationToken: UInt64
        private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
        private let token: AppAccessGateV1.ContentReadToken
        private let accessGate: AppAccessGateV1
        private let clock: any ApplicationClock
        private let startedAt: Date
        private let ledger: OwnedStorageLedgerV1
        private let applicationSupportURL: URL
        private let content: EvidenceBundleStore
        private let interruption: @Sendable (FieldReferenceInterruptionPointV1) async throws -> Void
        private var expectedRevision: WorkspaceRevisionV1
        private var expectedSourceSHA256: String
        private var reservation: OwnedStorageReservationV1?

        init(session: StoreSessionCoordinator, token: AppAccessGateV1.ContentReadToken,
             accessGate: AppAccessGateV1, clock: any ApplicationClock,
             ledger: OwnedStorageLedgerV1, applicationSupportURL: URL,
             interruption: @escaping @Sendable (FieldReferenceInterruptionPointV1) async throws -> Void) throws {
            guard UIApplication.shared.isProtectedDataAvailable else {
                throw ProductionFieldReferenceLifecycleFailureV1.protectedDataUnavailable
            }
            self.session = session; writer = session.workspaceWriter
            workspaceID = session.workspaceID; generationID = session.generationID
            uiGenerationToken = session.uiGenerationToken
            rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
            self.token = token; self.accessGate = accessGate; self.clock = clock
            startedAt = clock.now(); self.ledger = ledger
            self.applicationSupportURL = applicationSupportURL
            self.interruption = interruption
            content = EvidenceBundleStore(generationRootURL: session.generationRootURL,
                expectedGenerationRootIdentity: rootIdentity)
            expectedRevision = try session.workspaceWriter.currentRevision()
            expectedSourceSHA256 = try Sources(context: session.modelContext, workspaceID: session.workspaceID).sha256()
            guard startedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw ProductionFieldReferenceLifecycleFailureV1.clockChanged
            }
        }

        func coordinator() -> FieldReferencePackCoordinatorV1 {
            let adapter = FieldReferencePackLifecycleAdapterV1(operations: .init(
                persist: { try await self.persist($0) },
                validateReadback: { try await self.validateReadback($0) },
                readinessInputs: { try await self.readinessInputs(release: $0, binding: $1, evaluatedAt: $2) },
                discardIfUnbound: { try await self.discardIfUnbound($0) },
                acceptedRelease: { try await self.accepted(.importRelease($0)) },
                appendRelease: { try await self.commit(.importRelease($0)) },
                acceptedBinding: { try await self.accepted(.bind(value: $0, release: $1)) },
                appendBinding: { try await self.commit(.bind(value: $0, release: $1)) },
                interruption: interruption
            ))
            return .init(content: adapter, writer: adapter)
        }

        func validate() async throws {
            try await accessGate.validateContentRead(token, for: .bulkImport)
            try Task.checkCancellation()
            try validateSynchronous()
        }

        private func validateSynchronous() throws {
            guard writer === session.workspaceWriter, workspaceID == session.workspaceID,
                  generationID == session.generationID, uiGenerationToken == session.uiGenerationToken else {
                throw ProductionFieldReferenceLifecycleFailureV1.sessionChanged
            }
            guard UIApplication.shared.isProtectedDataAvailable else {
                throw ProductionFieldReferenceLifecycleFailureV1.protectedDataUnavailable
            }
            guard try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL) == rootIdentity,
                  try writer.currentRevision() == expectedRevision,
                  try sources().sha256() == expectedSourceSHA256 else {
                throw ProductionFieldReferenceLifecycleFailureV1.sourcesChanged
            }
            let now = clock.now()
            guard now.timeIntervalSinceReferenceDate.isFinite, now >= startedAt else {
                throw ProductionFieldReferenceLifecycleFailureV1.clockChanged
            }
        }

        private func sources() throws -> Sources {
            try .init(context: session.modelContext, workspaceID: workspaceID)
        }

        private func metadata(_ release: FieldReferenceReleaseV1) throws -> FieldReferenceImportedContentV1 {
            try release.validate()
            guard release.workspaceID == workspaceID else { throw FieldReferencePackFailureV1.wrongWorkspace }
            guard let metadata = release.importedContent else { throw FieldReferencePackFailureV1.unsupported }
            for entry in metadata.entries {
                guard try EvidenceBundleStore.fieldReferenceLocator(for: entry.reference) == entry.locator else {
                    throw FieldReferencePackFailureV1.unsupported
                }
            }
            return metadata
        }

        private func persist(_ plan: FieldReferenceImportPlanV1) async throws {
            try await validate()
            _ = try FieldReferenceImportPlanV1(release: plan.release, items: plan.items)
            _ = try metadata(plan.release)
            _ = try ledger.observeOfflineReadiness(expectedApplicationSupportURL: applicationSupportURL)
            // Independent in-flight attempts must not share a reservation that
            // one caller could release while another is still writing.
            let attempt = try OwnedStorageAttemptIDV1(workspaceID: workspaceID,
                generationID: generationID, mutationID: .init(rawValue: UUID()))
            reservation = try ledger.reserve(attemptID: attempt,
                requiredBytes: Int64(plan.items.reduce(0) { $0 + $1.bytes.count }))
            for item in plan.items {
                try await validate()
                _ = try await content.persistFieldReferenceItem(item,
                    workspaceID: workspaceID, mutationID: plan.release.mutationID)
                try await validate()
            }
        }

        func releaseReservation() {
            if let reservation { ledger.release(reservation: reservation) }
            reservation = nil
        }

        private func present(_ release: FieldReferenceReleaseV1) async throws
            -> [FieldReferenceImportedContentV1.Entry] {
            let metadata = try metadata(release)
            try await validate()
            let result = try await content.readFieldReferenceContent(metadata)
            try await validate()
            return result
        }

        private func validateReadback(_ plan: FieldReferenceImportPlanV1) async throws {
            _ = try FieldReferenceImportPlanV1(release: plan.release, items: plan.items)
            guard try await present(plan.release) == metadata(plan.release).entries else {
                throw FieldReferencePackFailureV1.missingContent
            }
        }

        func discardIfUnbound(_ plan: FieldReferenceImportPlanV1) async throws {
            _ = try FieldReferenceImportPlanV1(release: plan.release, items: plan.items)
            let present = try await present(plan.release)
            let canonical = try sources().readiness.releases.compactMap(\.importedContent)
                .flatMap(\.entries)
            try await validate()
            // A retained exact canonical reference is positive ownership. No
            // C23-only scan can prove generic content globally unreferenced.
            guard present.allSatisfy({ canonical.contains($0) }) else {
                throw ProductionFieldReferenceLifecycleFailureV1.cleanupDeferred
            }
        }

        private func readinessInputs(release: FieldReferenceReleaseV1,
            binding: FieldReferenceBindingV1, evaluatedAt: Date) async throws -> FieldReferenceReadinessInputsV1 {
            try binding.validate(release: release)
            let present = try await present(release)
            let source = try sources()
            try source.validateSubject(binding, at: clock.now())
            guard source.readiness.releases.contains(release) else { throw FieldReferencePackFailureV1.wrongRelease }
            return .init(references: present.map(\.reference), locators: present.map(\.locator),
                knownSupersededReleaseIDs: Set(source.readiness.releases.compactMap(\.supersedesReleaseID)),
                knownRevokedReleaseIDs: Set(source.readiness.releases.filter { $0.releaseDisposition == .revoked }.map(\.releaseID)),
                evaluatedAt: evaluatedAt, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        }

        private func accepted(_ mutation: FieldReferenceMutationV1) async throws -> FieldReferenceWriteReceiptV1? {
            try await validate()
            guard let receipt = try writer.fieldReferenceReceipt(for: mutation) else { return nil }
            return try writeReceipt(receipt, mutation: mutation)
        }

        private func commit(_ mutation: FieldReferenceMutationV1) async throws -> FieldReferenceWriteReceiptV1 {
            switch mutation {
            case let .importRelease(release):
                guard try await present(release) == metadata(release).entries else {
                    throw FieldReferencePackFailureV1.missingContent
                }
            case let .bind(binding, release):
                let inputs = try await readinessInputs(release: release, binding: binding, evaluatedAt: clock.now())
                let readiness = try FieldReferenceOfflineReadinessV1(release: release, binding: binding, inputs: inputs)
                guard readiness.availability == .readyOffline else { throw FieldReferencePackFailureV1.missingContent }
            }
            try await validate()
            // No await between the final source/clock checks and sole-writer
            // commit. A freshly expired release cannot be newly bound.
            if case let .bind(binding, release) = mutation {
                let now = clock.now()
                try sources().validateSubject(binding, at: now)
                guard now >= binding.boundAt, release.expiresAt.map({ $0 > now }) ?? true else {
                    throw FieldReferencePackFailureV1.staleBinding
                }
            }
            let receipt = try writer.commitFieldReference(mutation)
            expectedRevision = try writer.currentRevision()
            expectedSourceSHA256 = try sources().sha256()
            return try writeReceipt(receipt, mutation: mutation)
        }

        private func writeReceipt(_ receipt: MutationReceiptV1, mutation: FieldReferenceMutationV1) throws
            -> FieldReferenceWriteReceiptV1 {
            _ = try FieldReferenceMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            let digest: String
            switch mutation {
            case let .importRelease(release): digest = release.releaseSHA256
            case let .bind(binding, _): digest = binding.bindingSHA256
            }
            return try .init(mutationID: mutation.mutationID, postImageSHA256: digest,
                canonicalMutationReceiptSHA256: receipt.canonicalSHA256())
        }
    }

    private struct Sources: Encodable {
        let readiness: ProductionOfflineReadinessSourceClosureV1
        let manifests: [WorkPacketManifestV1]
        let claims: [WorkItemClaimV1]
        let leases: [WorkLeaseV1]
        let releases: [WorkReleaseV1]
        let handoffs: [WorkHandoffV1]

        @MainActor init(context: ModelContext, workspaceID: WorkspaceID) throws {
            readiness = try .init(context: context, workspaceID: workspaceID)
            let workspace = workspaceID.rawValue
            manifests = try context.fetch(FetchDescriptor<WorkPacketManifestRow>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { $0.manifestID.uuidString < $1.manifestID.uuidString }
            claims = try context.fetch(FetchDescriptor<WorkItemClaimRow>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { $0.claimID.uuidString < $1.claimID.uuidString }
            leases = try context.fetch(FetchDescriptor<WorkLeaseRow>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { $0.leaseID.uuidString < $1.leaseID.uuidString }
            releases = try context.fetch(FetchDescriptor<WorkReleaseRow>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }
            handoffs = try context.fetch(FetchDescriptor<WorkHandoffRow>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { $0.handoffID.uuidString < $1.handoffID.uuidString }
            guard Set(manifests.map(\.manifestID)).count == manifests.count,
                  Set(manifests.map { "\($0.packetID)|\($0.packetVersion)" }).count == manifests.count,
                  Set(claims.map(\.claimID)).count == claims.count,
                  Set(leases.map(\.leaseID)).count == leases.count,
                  Set(releases.map(\.releaseID)).count == releases.count,
                  Set(handoffs.map(\.handoffID)).count == handoffs.count else {
                throw ProductionFieldReferenceLifecycleFailureV1.sourcesChanged
            }
            let references = try Set(manifests.map(WorkPacketManifestReferenceV1.init))
            let itemReferences = try Set(manifests.flatMap { manifest in
                try manifest.items.map { try WorkPacketItemReferenceV1(manifest: manifest, item: $0) }
            })
            guard claims.allSatisfy({ references.contains($0.manifest) && itemReferences.contains($0.item) }),
                  leases.allSatisfy({ lease in
                      itemReferences.contains(lease.item) && claims.contains {
                          $0.claimID == lease.claimID && $0.item == lease.item && $0.holder.actor == lease.holder.actor
                      }
                  }), releases.allSatisfy({ itemReferences.contains($0.item) }),
                  handoffs.allSatisfy({ itemReferences.contains($0.item) }) else {
                throw ProductionFieldReferenceLifecycleFailureV1.sourcesChanged
            }
        }

        func sha256() throws -> String { try MyDayCanonicalCodecV1.sha256(self) }

        func validateSubject(_ binding: FieldReferenceBindingV1, at instant: Date) throws {
            let actualRevision: UInt64
            let actualState: FieldReferenceSubjectStateV1
            switch binding.subjectKind {
            case .roundSession:
                guard let round = try RoundSessionHistoryValidatorV1.validate(
                    readiness.rounds.filter { $0.sessionID == binding.subjectID },
                    workspaceID: binding.workspaceID, sessionID: binding.subjectID) else {
                    throw FieldReferencePackFailureV1.staleBinding
                }
                actualRevision = round.revision
                actualState = round.state == .completed || round.state == .archived ? .finalized : .active
            case .workPacket:
                let history = manifests.filter { $0.packetID == binding.subjectID }
                guard let current = history.max(by: { $0.packetVersion < $1.packetVersion }) else {
                    throw FieldReferencePackFailureV1.staleBinding
                }
                let projection = try WorkPacketProjectionBuilderV1.rebuild(workspaceID: binding.workspaceID,
                    manifest: current, claims: claims, leases: leases, releases: releases, handoffs: handoffs, at: instant)
                guard projection.items.allSatisfy({ $0.exceptions.isEmpty }) else {
                    throw FieldReferencePackFailureV1.staleBinding
                }
                actualRevision = current.packetVersion
                actualState = projection.items.allSatisfy({ $0.currentClaim == nil && $0.latestRelease?.reason == .completed })
                    ? .finalized : .active
            }
            guard binding.subjectRevision == actualRevision, binding.subjectState == actualState else {
                throw FieldReferencePackFailureV1.staleBinding
            }
        }
    }
}

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
    init(writer: WorkspaceWriterV1) { self.writer = writer }

    convenience init(writer: WorkspaceWriterV1, journalStore: MutationJournalStoreV1) {
        self.init(writer: writer)
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
        guard let receipt = try writer.fieldReferenceReceipt(for: mutation) else { return nil }
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
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_OfflineReadiness_FieldReferencePackLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/OfflineReadiness/FieldReferencePackLifecycleAdapterV1.swift", role: .pack)
}

enum C31LightingConsumerBoundary_Infrastructure_OfflineReadiness_FieldReferencePackLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/reference-pack-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_OfflineReadiness_FieldReferencePackLifecycleAdapterV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_OfflineReadiness_FieldReferencePackLifecycleAdapterV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row146 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_OfflineReadiness_FieldReferencePackLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_OfflineReadiness_FieldReferencePackLifecycleAdapterV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}
