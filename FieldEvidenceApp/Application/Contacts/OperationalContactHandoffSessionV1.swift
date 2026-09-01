import Foundation

/// An opaque, foreground-only restoration marker supplied by the owning Site
/// or Party surface. It carries stable UI identity, never a destination or
/// contact value, and is discarded when the handoff session is dismissed.
struct OperationalContactHandoffRestorationTokenV1: Equatable, Sendable {
    let subject: OperationalContactHandoffSubjectV1
    let selectedStableID: UUID?
    let scrollAnchorID: String?
    let focusIdentifier: String?
}

/// One explicitly reviewed action in a foreground handoff chooser. The
/// display value is customer work data and is intentionally non-Codable.
struct OperationalContactHandoffActionPresentationV1: Equatable, Sendable {
    let actionID: UUID
    let route: OperationalContactHandoffRouteV1
    let kind: SystemHandoffKindV1
    let displayValue: String
    let preferred: Bool
}

/// The complete, ephemeral chooser state for one exact Site or Party.
struct OperationalContactHandoffPresentationV1: Equatable, Sendable {
    let sessionID: UUID
    let snapshot: OperationalContactHandoffPresentationSnapshotV1
    let actions: [OperationalContactHandoffActionPresentationV1]
    let restorationToken: OperationalContactHandoffRestorationTokenV1
}

/// A visible no-action state. These values describe AssetRounds' current
/// source validation only; they do not claim anything about an external app.
struct OperationalContactHandoffUnavailablePresentationV1: Equatable, Sendable {
    let disposition: SystemHandoffDispositionV1
    let restorationToken: OperationalContactHandoffRestorationTokenV1

    var truthfulText: String {
        switch disposition {
        case .targetMissing:
            return "The selected Site or Party is no longer available. No system handoff was started."
        case .targetInvalid:
            return "The selected handoff value is unavailable. No system handoff was started."
        case .targetStale:
            return "The selected handoff changed. Review the current value before trying again."
        case .systemUnavailable:
            return "A system handoff is unavailable on this device."
        case .systemRejected:
            return "The system did not accept the handoff."
        case .cancelledBeforeHandoff:
            return "The handoff was cancelled before the system was opened."
        case .handedOffToSystem:
            return "The system accepted the handoff. Completion is not confirmed."
        }
    }
}

enum OperationalContactHandoffPreparationV1: Equatable, Sendable {
    case ready(OperationalContactHandoffPresentationV1)
    case unavailable(OperationalContactHandoffUnavailablePresentationV1)
}

/// Result text is deliberately restricted to system-presentation truth. It
/// never claims that a call, message, email, route, or delivery completed.
struct OperationalContactHandoffExecutionV1: Equatable, Sendable {
    let actionID: UUID
    let result: SystemHandoffResultV1
    let copyFallbackAvailable: Bool

    var truthfulText: String {
        switch result.disposition {
        case .handedOffToSystem:
            return "Handed off to the system. Completion is not confirmed."
        case .targetMissing:
            return "The selected source is no longer available. No system handoff was started."
        case .targetStale:
            return "The selected source changed. Review the current value before trying again."
        case .targetInvalid:
            return "The selected handoff value is unavailable. No system handoff was started."
        case .systemUnavailable:
            return "A system handoff is unavailable on this device. No handoff was completed."
        case .systemRejected:
            return "The system did not accept the handoff. No handoff was completed."
        case .cancelledBeforeHandoff:
            return "The handoff was cancelled before the system was opened."
        }
    }
}

enum OperationalContactHandoffCopyFallbackDispositionV1: Equatable, Sendable {
    case copied
    case unavailable
}

enum OperationalContactHandoffSessionFailureV1: Error, Equatable {
    case invalidRestorationToken
    case invalidEphemeralIdentifier
    case sessionUnavailable
    case actionUnavailable
}

/// Clipboard access is injected so the application coordinator can be tested
/// without a global pasteboard and never records copied customer work data.
@MainActor
protocol OperationalContactHandoffValueCopyingV1: AnyObject {
    func copyHandoffValue(_ value: String)
}

@MainActor
final class ClosureOperationalContactHandoffValueCopierV1:
    OperationalContactHandoffValueCopyingV1 {
    private let operation: (String) -> Void

    init(operation: @escaping (String) -> Void) {
        self.operation = operation
    }

    func copyHandoffValue(_ value: String) {
        operation(value)
    }
}

/// C31's foreground-only coordinator. It intentionally owns no workspace
/// writer: durable C46 intents remain available to their existing owner, while
/// this user-interface session creates no intent row, receipt, history, or
/// other canonical effect.
@MainActor
final class OperationalContactHandoffSessionV1 {
    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    private struct DraftAction {
        let presentation: OperationalContactHandoffActionPresentationV1
        let intent: SystemHandoffIntentV1
        var copyFallbackValue: String?
        var lastDisposition: SystemHandoffDispositionV1?
    }

    private struct Draft {
        let presentation: OperationalContactHandoffPresentationV1
        var actions: [UUID: DraftAction]
    }

    private let workspaceID: WorkspaceID
    private let query: any OperationalContactHandoffQueryingV1
    private let system: any SystemHandoffPortV1
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let clipboard: any OperationalContactHandoffValueCopyingV1
    private var drafts = [UUID: Draft]()

    init(
        workspaceID: WorkspaceID,
        query: any OperationalContactHandoffQueryingV1,
        system: any SystemHandoffPortV1,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        clipboard: any OperationalContactHandoffValueCopyingV1
    ) {
        self.workspaceID = workspaceID
        self.query = query
        self.system = system
        self.clock = clock
        self.idSource = idSource
        self.clipboard = clipboard
    }

    func prepare(
        subject: OperationalContactHandoffSubjectV1,
        restorationToken: OperationalContactHandoffRestorationTokenV1
    ) async -> OperationalContactHandoffPreparationV1 {
        guard restorationToken.subject == subject else {
            return .unavailable(.init(
                disposition: .targetInvalid,
                restorationToken: restorationToken
            ))
        }
        do {
            guard let snapshot = try await query.currentHandoffPresentationSnapshot(
                workspaceID: workspaceID,
                subject: subject
            ) else {
                return .unavailable(.init(
                    disposition: .targetMissing,
                    restorationToken: restorationToken
                ))
            }
            let sessionID = try nextIdentifier()
            var actions = [UUID: DraftAction]()
            var actionOrder = [UUID]()

            func appendAction(
                route: OperationalContactHandoffRouteV1,
                kind: SystemHandoffKindV1,
                target: SystemHandoffTargetReferenceV1,
                displayValue: String,
                preferred: Bool
            ) throws {
                let actionID = try nextIdentifier()
                let intent = try SystemHandoffIntentV1(
                    intentID: try nextIdentifier(),
                    workspaceID: workspaceID,
                    kind: kind,
                    target: target,
                    reviewedAt: clock.now(),
                    revision: 1,
                    mutationID: try MutationIDV1(rawValue: nextIdentifier())
                )
                guard actions[actionID] == nil else {
                    throw OperationalContactHandoffSessionFailureV1.invalidEphemeralIdentifier
                }
                actions[actionID] = DraftAction(
                    presentation: OperationalContactHandoffActionPresentationV1(
                        actionID: actionID,
                        route: route,
                        kind: kind,
                        displayValue: displayValue,
                        preferred: preferred
                    ),
                    intent: intent,
                    copyFallbackValue: nil,
                    lastDisposition: nil
                )
                actionOrder.append(actionID)
            }

            switch snapshot.subject {
            case let .site(siteID):
                guard let directions = snapshot.directions else {
                    throw OperationalContactFailureV1.invalidHandoffTarget
                }
                let destination = try directions.preferredDestination()
                try appendAction(
                    route: .directions(siteID: siteID),
                    kind: .directions,
                    target: directions.currentTarget,
                    displayValue: Self.displayValue(for: destination),
                    preferred: true
                )

            case .party:
                for contact in snapshot.contacts {
                    switch contact.kind {
                    case .phone:
                        try appendAction(
                            route: .call(contactPointID: contact.contactPointID),
                            kind: .call,
                            target: contact.target,
                            displayValue: contact.displayValue,
                            preferred: contact.preferred
                        )
                        try appendAction(
                            route: .text(contactPointID: contact.contactPointID),
                            kind: .text,
                            target: contact.target,
                            displayValue: contact.displayValue,
                            preferred: contact.preferred
                        )
                    case .email:
                        try appendAction(
                            route: .email(contactPointID: contact.contactPointID),
                            kind: .email,
                            target: contact.target,
                            displayValue: contact.displayValue,
                            preferred: contact.preferred
                        )
                    }
                }
            }

            guard !actions.isEmpty else {
                return .unavailable(.init(
                    disposition: .targetMissing,
                    restorationToken: restorationToken
                ))
            }
            let presentation = OperationalContactHandoffPresentationV1(
                sessionID: sessionID,
                snapshot: snapshot,
                actions: actionOrder.compactMap { actions[$0]?.presentation },
                restorationToken: restorationToken
            )
            drafts[sessionID] = Draft(presentation: presentation, actions: actions)
            return .ready(presentation)
        } catch {
            return .unavailable(.init(
                disposition: .targetInvalid,
                restorationToken: restorationToken
            ))
        }
    }

    /// Re-reads the selected target immediately before the one OS call. A
    /// source changed or deleted while the chooser was visible is never reused.
    func perform(
        sessionID: UUID,
        actionID: UUID
    ) async throws -> OperationalContactHandoffExecutionV1 {
        guard let draft = drafts[sessionID] else {
            throw OperationalContactHandoffSessionFailureV1.sessionUnavailable
        }
        guard let action = draft.actions[actionID] else {
            throw OperationalContactHandoffSessionFailureV1.actionUnavailable
        }
        let result: SystemHandoffResultV1
        var copyFallbackValue: String?
        if Task.isCancelled {
            result = try makeResult(
                intent: action.intent,
                disposition: .cancelledBeforeHandoff,
                revision: action.intent.target.expectedRevision
            )
        } else if let disposition = await currentSubjectDisposition(
            draft.presentation.snapshot.subject,
            action: action
        ) {
            result = try makeResult(intent: action.intent, disposition: disposition)
        } else {
            switch await query.resolveForHandoff(action.intent) {
            case .targetMissing:
                result = try makeResult(intent: action.intent, disposition: .targetMissing)
            case .targetStale:
                result = try makeResult(intent: action.intent, disposition: .targetStale)
            case .targetInvalid:
                result = try makeResult(intent: action.intent, disposition: .targetInvalid)
            case let .resolved(request):
                if Task.isCancelled {
                    result = try makeResult(
                        intent: action.intent,
                        disposition: .cancelledBeforeHandoff,
                        revision: request.currentTarget.expectedRevision
                    )
                } else {
                    result = await system.handOff(request)
                    if result.disposition == .systemUnavailable
                        || result.disposition == .systemRejected {
                        copyFallbackValue = Self.copyValue(for: request.destination)
                    }
                }
            }
        }
        guard var currentDraft = drafts[sessionID],
              var currentAction = currentDraft.actions[actionID],
              currentAction.intent == action.intent else {
            throw OperationalContactHandoffSessionFailureV1.sessionUnavailable
        }
        currentAction.copyFallbackValue = copyFallbackValue
        currentAction.lastDisposition = result.disposition
        currentDraft.actions[actionID] = currentAction
        drafts[sessionID] = currentDraft
        return OperationalContactHandoffExecutionV1(
            actionID: actionID,
            result: result,
            copyFallbackAvailable: copyFallbackValue != nil
        )
    }

    /// Revalidates the owning Site or Party projection at tap time. A contact
    /// row cannot remain actionable after its selected Party is removed or
    /// retired, even if the contact row itself has not changed yet.
    private func currentSubjectDisposition(
        _ subject: OperationalContactHandoffSubjectV1,
        action: DraftAction
    ) async -> SystemHandoffDispositionV1? {
        let snapshot: OperationalContactHandoffPresentationSnapshotV1
        do {
            guard let current = try await query.currentHandoffPresentationSnapshot(
                workspaceID: workspaceID,
                subject: subject
            ) else { return .targetMissing }
            snapshot = current
        } catch {
            return .targetInvalid
        }
        guard snapshot.subject == subject else { return .targetInvalid }
        switch subject {
        case let .site(siteID):
            guard action.presentation.route == .directions(siteID: siteID),
                  action.presentation.kind == .directions,
                  let directions = snapshot.directions else {
                return .targetInvalid
            }
            return directions.currentTarget == action.intent.target
                ? nil : .targetStale

        case .party:
            guard let contact = snapshot.contacts.first(where: {
                $0.contactPointID == action.intent.target.targetID
            }) else { return .targetMissing }
            let compatibleKind: Bool
            switch (contact.kind, action.presentation.kind) {
            case (.phone, .call), (.phone, .text), (.email, .email):
                compatibleKind = true
            default:
                compatibleKind = false
            }
            guard compatibleKind else { return .targetInvalid }
            return contact.target == action.intent.target ? nil : .targetStale
        }
    }

    /// Copies only a freshly resolved, valid value after a system-unavailable
    /// or system-rejected outcome. It never substitutes an alternate target.
    func copyFallback(
        sessionID: UUID,
        actionID: UUID
    ) -> OperationalContactHandoffCopyFallbackDispositionV1 {
        guard let action = drafts[sessionID]?.actions[actionID],
              (action.lastDisposition == .systemUnavailable
                || action.lastDisposition == .systemRejected),
              let value = action.copyFallbackValue else {
            return .unavailable
        }
        clipboard.copyHandoffValue(value)
        return .copied
    }

    /// Both cancel and normal dismissal erase the entire in-memory chooser and
    /// hand its exact caller-owned restoration marker back to the presenter.
    func cancel(sessionID: UUID) -> OperationalContactHandoffRestorationTokenV1? {
        dismiss(sessionID: sessionID)
    }

    func dismiss(sessionID: UUID) -> OperationalContactHandoffRestorationTokenV1? {
        drafts.removeValue(forKey: sessionID)?.presentation.restorationToken
    }

    private func nextIdentifier() throws -> UUID {
        let value = idSource.makeID()
        guard value != Self.zeroUUID else {
            throw OperationalContactHandoffSessionFailureV1.invalidEphemeralIdentifier
        }
        return value
    }

    private func makeResult(
        intent: SystemHandoffIntentV1,
        disposition: SystemHandoffDispositionV1,
        revision: UInt64? = nil
    ) throws -> SystemHandoffResultV1 {
        try SystemHandoffResultV1(
            intentID: intent.intentID,
            disposition: disposition,
            evaluatedAt: clock.now(),
            resolvedTargetRevision: revision
        )
    }

    private static func displayValue(for destination: SystemHandoffDestinationV1) -> String {
        switch destination {
        case let .exactAddress(value), let .phone(value), let .email(value):
            return value
        case let .geographicCoordinate(latitude, longitude):
            return "\(latitude),\(longitude)"
        }
    }

    private static func copyValue(for destination: SystemHandoffDestinationV1) -> String? {
        displayValue(for: destination)
    }
}
