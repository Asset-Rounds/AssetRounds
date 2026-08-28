import Foundation
import SwiftData

struct DraftCommitSagaRecoverySummaryV1: Equatable, Sendable {
    let checkpointCount: Int
    let activeSagaCount: Int
    let reservationCount: Int
    let recoveryRequiredDraftIDs: [UUID]
}

@MainActor
final class DraftCommitSagaRecoveryV1 {
    private let context: ModelContext
    private let receiptRecovery: MutationReceiptRecoveryServiceV1?

    init(modelContext: ModelContext, receiptRecovery: MutationReceiptRecoveryServiceV1? = nil) {
        context = modelContext
        self.receiptRecovery = receiptRecovery
    }

    func reconcile() throws -> DraftCommitSagaRecoverySummaryV1 {
        try receiptRecovery?.recoverFieldDraftEffectsBeforeWriterActivation()
        let checkpoints = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map { try $0.value() }
        let stages = try context.fetch(FetchDescriptor<AttachmentStagingItemRow>()).map { try $0.value() }
        let sagas = try context.fetch(FetchDescriptor<DraftCommitSagaRow>()).map { try $0.value() }
        let reservations = try context.fetch(FetchDescriptor<DraftContentReservationRow>()).map { try $0.value() }
        let commitReceipts = try context.fetch(FetchDescriptor<DraftCommitReceiptRow>()).map { try $0.value() }
        let discardReceipts = try context.fetch(FetchDescriptor<DraftDiscardReceiptRow>()).map { try $0.value() }

        guard Set(checkpoints.map(\.draftID)).count == checkpoints.count,
              Set(stages.map(\.stageID)).count == stages.count,
              Set(sagas.map(\.sagaID)).count == sagas.count,
              Set(reservations.map(\.reservationID)).count == reservations.count,
              Set(commitReceipts.map(\.receiptID)).count == commitReceipts.count,
              Set(discardReceipts.map(\.receiptID)).count == discardReceipts.count else {
            throw FieldDraftFailureV1.invalidValue
        }
        let checkpointByID = Dictionary(uniqueKeysWithValues: checkpoints.map { ($0.draftID, $0) })
        let stageByID = Dictionary(uniqueKeysWithValues: stages.map { ($0.stageID, $0) })
        let sagaByID = Dictionary(uniqueKeysWithValues: sagas.map { ($0.sagaID, $0) })
        let successorCounts = Dictionary(grouping: sagas.compactMap(\.predecessorSagaID), by: { $0 })
        let receiptsBySaga = Dictionary(grouping: commitReceipts, by: \.sagaID)
        let discardReceiptsByDraft = Dictionary(grouping: discardReceipts, by: \.draftID)
        guard successorCounts.values.allSatisfy({ $0.count == 1 }),
              receiptsBySaga.values.allSatisfy({ $0.count == 1 }),
              discardReceiptsByDraft.values.allSatisfy({ $0.count == 1 }) else {
            throw FieldDraftFailureV1.invalidTransition
        }

        for stage in stages {
            guard let checkpoint = checkpointByID[stage.draftID],
                  checkpoint.workspaceID == stage.workspaceID,
                  checkpoint.stageIDs.contains(stage.stageID) else {
                throw FieldDraftFailureV1.missingContent
            }
        }
        for reservation in reservations {
            guard let checkpoint = checkpointByID[reservation.draftID],
                  let stage = stageByID[reservation.stageID],
                  checkpoint.workspaceID == reservation.workspaceID,
                  stage.workspaceID == reservation.workspaceID,
                  stage.contentDigest == reservation.contentDigest else {
                throw FieldDraftFailureV1.missingContent
            }
        }
        for saga in sagas {
            guard checkpointByID[saga.draftID]?.workspaceID == saga.workspaceID else {
                throw FieldDraftFailureV1.wrongWorkspace
            }
            if let predecessorID = saga.predecessorSagaID {
                guard let predecessor = sagaByID[predecessorID] else {
                    throw FieldDraftFailureV1.invalidTransition
                }
                try saga.validateSuccessor(of: predecessor)
            }
        }
        for receipt in commitReceipts {
            guard let terminalSaga = sagaByID[receipt.sagaID],
                  let checkpoint = checkpointByID[receipt.draftID],
                  terminalSaga.workspaceID == receipt.workspaceID,
                  terminalSaga.draftID == receipt.draftID,
                  terminalSaga.state == .draftRetired,
                  terminalSaga.plan.planSHA256 == receipt.commitPlanSHA256,
                  checkpoint.state == .committed,
                  checkpoint.lastDurableMutationID == receipt.mutationID,
                  checkpoint.lastReceiptSHA256 == receipt.receiptSHA256,
                  try sagaDigestChain(endingAt: terminalSaga, byID: sagaByID) == receipt.sagaEventSHA256Chain,
                  try consumedContent(for: terminalSaga.plan, reservations: reservations) == receipt.consumedStageToContentID else {
                throw FieldDraftFailureV1.missingReceipt
            }
        }
        for receipt in discardReceipts {
            guard let checkpoint = checkpointByID[receipt.draftID],
                  checkpoint.workspaceID == receipt.workspaceID,
                  checkpoint.state == .discarded,
                  checkpoint.lastDurableMutationID == receipt.mutationID,
                  checkpoint.lastReceiptSHA256 == receipt.receiptSHA256 else {
                throw FieldDraftFailureV1.missingReceipt
            }
        }

        let active = sagas.filter { $0.state != .draftRetired }
        let required = Set(
            checkpoints.filter { $0.state == .recoveryRequired }.map(\.draftID)
                + active.filter {
                    $0.state == .recoveryRequired
                        || $0.state == .contentPromotedUnbound
                        || $0.state == .targetCommitted
                        || $0.state == .draftRetirePending
                }.map(\.draftID)
        )
        return .init(
            checkpointCount: checkpoints.count,
            activeSagaCount: active.count,
            reservationCount: reservations.count,
            recoveryRequiredDraftIDs: required.sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func sagaDigestChain(
        endingAt terminal: DraftCommitSagaV1,
        byID: [UUID: DraftCommitSagaV1]
    ) throws -> [String] {
        var current: DraftCommitSagaV1? = terminal
        var seen = Set<UUID>()
        var reverse: [String] = []
        while let saga = current {
            guard seen.insert(saga.sagaID).inserted else {
                throw FieldDraftFailureV1.invalidTransition
            }
            reverse.append(saga.sagaSHA256)
            current = try saga.predecessorSagaID.map {
                guard let predecessor = byID[$0] else {
                    throw FieldDraftFailureV1.invalidTransition
                }
                return predecessor
            }
        }
        return Array(reverse.reversed())
    }

    private func consumedContent(
        for plan: DraftCommitPlanV1,
        reservations: [DraftContentReservationV1]
    ) throws -> [String: String] {
        let values = reservations.filter {
            $0.workspaceID == plan.workspaceID
                && $0.draftID == plan.draftID
                && $0.commitPlanSHA256 == plan.planSHA256
        }
        guard values.count == plan.stageDigests.count,
              Set(values.map(\.stageID)).count == values.count else {
            throw FieldDraftFailureV1.missingContent
        }
        return Dictionary(
            uniqueKeysWithValues: values.map {
                ($0.stageID.uuidString, $0.locator.contentID)
            }
        )
    }
}
