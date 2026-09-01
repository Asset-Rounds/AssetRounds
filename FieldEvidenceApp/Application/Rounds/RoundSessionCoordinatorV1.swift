import Foundation

@MainActor protocol RoundSessionCurrentReadingV1: AnyObject {
    func roundSessionHistory(workspaceID: WorkspaceID, sessionID: UUID) throws -> [RoundSessionV1]
}

@MainActor protocol RoundSessionCanonicalWritingV1: AnyObject {
    func commitRoundSession(_ mutation: RoundSessionMutationV1) throws -> RoundSessionMutationReceiptV1
}

@MainActor protocol RoundSessionLiveAuthorityReadingV1: AnyObject {
    func publishedPackageRelease(for reference: RoundPackageReleaseReferenceV1) throws -> InspectionPackageReleaseV1?
    func contentReference(workspaceID: WorkspaceID, contentID: String) throws -> ContentReferenceV1?
    func assetExists(workspaceID: WorkspaceID, assetID: UUID) throws -> Bool
    func completionMatches(workspaceID: WorkspaceID, reference: RoundItemCompletionReferenceV1) throws -> Bool
}

@MainActor final class RoundSessionCoordinatorV1 {
    private let workspaceID: WorkspaceID
    private let reader: any RoundSessionCurrentReadingV1
    private let writer: any RoundSessionCanonicalWritingV1
    private let authority: any RoundSessionLiveAuthorityReadingV1

    init(workspaceID: WorkspaceID, reader: any RoundSessionCurrentReadingV1,
         writer: any RoundSessionCanonicalWritingV1, authority: any RoundSessionLiveAuthorityReadingV1) {
        self.workspaceID = workspaceID; self.reader = reader; self.writer = writer; self.authority = authority
    }

    func history(sessionID: UUID) throws -> [RoundSessionV1] { try validatedHistory(sessionID: sessionID) }
    func current(sessionID: UUID) throws -> RoundSessionV1? { try validatedHistory(sessionID: sessionID).last }

    func save(_ mutation: RoundSessionMutationV1) throws -> RoundSessionMutationReceiptV1 {
        try mutation.validate(); guard mutation.workspaceID == workspaceID else { throw RoundSessionFailureV1.authorityMismatch }
        let history = try validatedHistory(sessionID: mutation.session.sessionID)
        if let prior = history.last { try mutation.session.validateSuccessor(of: prior); guard mutation.expectedRevision == prior.revision else { throw RoundSessionFailureV1.staleRevision } }
        else { guard mutation.expectedRevision == 0, mutation.session.revision == 1, mutation.session.predecessor == nil else { throw RoundSessionFailureV1.staleRevision } }
        try validateLiveAuthority(for: mutation.session, predecessor: history.last, validatingStoredFrontier: false)
        let receipt = try writer.commitRoundSession(mutation)
        guard receipt.sessionFrontier == (try mutation.session.reference) else { throw RoundSessionFailureV1.authorityMismatch }
        return receipt
    }

    /// C21's explicit start is an ordinary exact round successor. The
    /// existing writer/journal remains responsible for atomic effect-before-
    /// receipt recovery and idempotent mutation-ID replay.
    func persistScanToWorkStart(
        _ request: ScanToWorkStartRequestV1
    ) throws -> InstallationScanEntryReceiptV1 {
        try C21RoundSessionStartBoundaryV1.validate(request)
        let receipt = try save(request.roundMutation)
        return try InstallationScanEntryReceiptV1(
            request: request,
            roundMutationReceipt: receipt
        )
    }

    /// Persists the sole C21 round successor before a caller navigates to the
    /// derived next target. Retry/recovery remains the incumbent mutation-ID
    /// and journal receipt behavior of `save`.
    func persistRepetitiveCaptureCheckpoint(
        _ request: RepetitiveCaptureCheckpointRequestV1
    ) throws -> RepetitiveCaptureCheckpointReceiptV1 {
        try C21RoundSessionCheckpointBoundaryV1.validate(request)
        let receipt = try save(request.roundMutation)
        return try RepetitiveCaptureCheckpointReceiptV1(
            request: request,
            roundReceipt: receipt
        )
    }

    func validateCurrentFrontier(_ reference: RoundSessionReferenceV1) throws -> RoundSessionV1 {
        try reference.validate(); guard reference.workspaceID == workspaceID,
              let current = try current(sessionID: reference.sessionID), try current.reference == reference else { throw RoundSessionFailureV1.staleRevision }
        try validateLiveAuthority(for: current, predecessor: nil, validatingStoredFrontier: true); return current
    }

    private func validatedHistory(sessionID: UUID) throws -> [RoundSessionV1] {
        let values = try reader.roundSessionHistory(workspaceID: workspaceID, sessionID: sessionID)
        _ = try RoundSessionHistoryValidatorV1.validate(values, workspaceID: workspaceID, sessionID: sessionID)
        return values
    }

    private func validateLiveAuthority(for value: RoundSessionV1, predecessor: RoundSessionV1?, validatingStoredFrontier: Bool) throws {
        for item in value.items {
            let requiresLiveRequirements: Bool
            if validatingStoredFrontier {
                requiresLiveRequirements = false
            } else {
                switch value.transition {
                case .visitItem, .completeItem, .retryItem:
                    requiresLiveRequirements = value.transitionItemID == item.itemID
                case .create, .reviseSelection, .start, .markInaccessible, .skipItem,
                     .deferItem, .pause, .resume, .close, .archive:
                    requiresLiveRequirements = false
                }
            }
            if let release = try authority.publishedPackageRelease(for: item.requirement.packageRelease) {
                try item.requirement.packageRelease.validate(against: release)
            } else {
                guard !requiresLiveRequirements else {
                    throw RoundSessionFailureV1.authorityMismatch
                }
            }
            for reference in item.requirement.requiredContent {
                if let live = try authority.contentReference(
                    workspaceID: workspaceID,
                    contentID: reference.contentID
                ) {
                    guard live == reference else { throw RoundSessionFailureV1.authorityMismatch }
                } else {
                    guard !requiresLiveRequirements else {
                        throw RoundSessionFailureV1.authorityMismatch
                    }
                }
            }
            if let completion = item.completion {
                guard try authority.completionMatches(workspaceID: workspaceID, reference: completion) else { throw RoundSessionFailureV1.authorityMismatch }
            }
            if !(try authority.assetExists(workspaceID: workspaceID, assetID: item.selection.assetID)) {
                let priorItem = predecessor?.items.first(where: { $0.itemID == item.itemID })
                let preservedTerminal = priorItem.map { $0 == item && $0.disposition.isTerminal } ?? false
                guard (validatingStoredFrontier && item.disposition.isTerminal)
                        || preservedTerminal
                        || (item.disposition == .inaccessible && item.reason == .assetDeletedDuringSession) else {
                    throw RoundSessionFailureV1.authorityMismatch
                }
            }
        }
    }
}

extension WorkspaceWriterV1: RoundSessionCanonicalWritingV1 {}
