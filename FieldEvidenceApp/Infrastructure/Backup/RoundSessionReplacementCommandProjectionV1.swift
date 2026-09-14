import Foundation

enum RoundSessionReplacementCommandProjectionFailureV1: Error, Equatable {
    case invalidIdentity, invalidSource, collision, missingDependency
}

/// Exact historical Round values and commands, before one global replacement
/// sequencer seals their receipts. No current-row lookup or persistence occurs.
enum RoundSessionReplacementCommandProjectionV1 {
    struct Command: Equatable, Sendable {
        let source: ReferenceOwnerReplacementSourceV1.Entry
        let mutation: RoundSessionMutationV1
        let postImage: MutationPostImageV1
        let sourceDependencyMutationIDs: [MutationIDV1]
        let targetDependencyMutationIDs: [MutationIDV1]

        fileprivate init(source: ReferenceOwnerReplacementSourceV1.Entry,
                         mutation: RoundSessionMutationV1,
                         predecessor: Command?) throws {
            self.source = source; self.mutation = mutation
            postImage = try mutation.mutationPostImage
            sourceDependencyMutationIDs = predecessor.map { [$0.source.envelope.mutationID] } ?? []
            targetDependencyMutationIDs = predecessor.map { [$0.mutation.mutationID] } ?? []
        }
    }

    struct Projection: Equatable, Sendable {
        let source: ReferenceOwnerReplacementSourceV1.Source
        let identity: RestoreIdentityV1
        let commands: [Command]

        fileprivate init(source: ReferenceOwnerReplacementSourceV1.Source,
                         identity: RestoreIdentityV1, commands: [Command]) {
            self.source = source; self.identity = identity; self.commands = commands
        }

        func targetSession(for reference: RoundSessionReferenceV1) throws -> RoundSessionV1 {
            try reference.validate()
            let matches = try commands.filter { command in
                guard case let .applyRoundSession(original) = command.source.envelope.command else {
                    throw RoundSessionReplacementCommandProjectionFailureV1.invalidSource
                }
                return try original.session.reference == reference
            }
            guard matches.count == 1 else {
                throw RoundSessionReplacementCommandProjectionFailureV1.missingDependency
            }
            return matches[0].mutation.session
        }
    }

    static func project(source: ReferenceOwnerReplacementSourceV1.Source,
                        identity: RestoreIdentityV1) throws -> Projection {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard identity.mode == .replaceExisting,
              source.workspaceID.rawValue == identity.source.workspaceID,
              source.workspaceID.rawValue != zero,
              identity.targetPointer.workspaceID == identity.oldPointer.workspaceID,
              identity.targetPointer.workspaceID != zero,
              identity.targetPointer.generationID != zero,
              identity.targetPointer.generationID != identity.oldPointer.generationID else {
            throw RoundSessionReplacementCommandProjectionFailureV1.invalidIdentity
        }
        let originals = try source.entries.filter { $0.family == .roundSession }.map { entry in
            guard case let .applyRoundSession(mutation) = entry.envelope.command else {
                throw RoundSessionReplacementCommandProjectionFailureV1.invalidSource
            }
            return Original(entry: entry, mutation: mutation)
        }
        let allOriginalMutationIDs = try Set(source.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).mutationID
        })
        let targetWorkspace = WorkspaceID(rawValue: identity.targetPointer.workspaceID)
        var targetMutationIDs = Set<MutationIDV1>()
        var projected: [MutationIDV1: Command] = [:]
        let groups = Dictionary(grouping: originals, by: { $0.mutation.session.sessionID })
        for sessionID in groups.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let values = groups[sessionID] else {
                throw RoundSessionReplacementCommandProjectionFailureV1.invalidSource
            }
            let ordered = values.sorted { $0.mutation.session.revision < $1.mutation.session.revision }
            _ = try RoundSessionHistoryValidatorV1.validate(
                ordered.map { $0.mutation.session }, workspaceID: source.workspaceID,
                sessionID: sessionID
            )
            var predecessor: Command?
            var targetHistory: [RoundSessionV1] = []
            for original in ordered {
                let value = original.mutation.session
                let targetID = try identity.destinationRoundSessionMutationID(for: original.mutation.mutationID)
                guard !allOriginalMutationIDs.contains(targetID),
                      targetMutationIDs.insert(targetID).inserted,
                      projected[original.mutation.mutationID] == nil else {
                    throw RoundSessionReplacementCommandProjectionFailureV1.collision
                }
                var visitActors: [UUID: ActorSnapshotV1] = [:]
                for visit in value.items.compactMap(\.visit) {
                    let rebound = try actor(visit.recordedBy, workspaceID: targetWorkspace)
                    if let existing = visitActors.updateValue(rebound, forKey: rebound.snapshotID),
                       existing != rebound {
                        throw RoundSessionReplacementCommandProjectionFailureV1.invalidSource
                    }
                }
                // Reuse C05's exact item/content/visit transform. Its temporary
                // value retains the original mutation ID; the final constructor
                // below binds the reissued command and the projected predecessor.
                let rebound = try value.rebindingWorkspaceID(
                    targetWorkspace, rebasedPredecessor: predecessor?.mutation.session,
                    recordedBy: actor(value.recordedBy, workspaceID: targetWorkspace),
                    visitActors: visitActors
                )
                let target = try RoundSessionV1(
                    workspaceID: targetWorkspace, sessionID: value.sessionID,
                    predecessor: predecessor?.mutation.session, revision: value.revision,
                    mutationID: targetID, state: value.state, transition: value.transition,
                    transitionItemID: value.transitionItemID, items: rebound.items,
                    recordedBy: rebound.recordedBy, recordedAt: value.recordedAt
                )
                if let predecessor { try target.validateSuccessor(of: predecessor.mutation.session) }
                let mutation = try RoundSessionMutationV1(
                    workspaceID: targetWorkspace, expectedRevision: original.mutation.expectedRevision,
                    mutationID: targetID, session: target
                )
                let command = try Command(source: original.entry, mutation: mutation, predecessor: predecessor)
                projected[original.mutation.mutationID] = command
                predecessor = command; targetHistory.append(target)
            }
            _ = try RoundSessionHistoryValidatorV1.validate(
                targetHistory, workspaceID: targetWorkspace, sessionID: sessionID
            )
        }
        guard projected.count == originals.count else {
            throw RoundSessionReplacementCommandProjectionFailureV1.invalidSource
        }
        let commands = try originals.map { original in
            guard let command = projected[original.mutation.mutationID] else {
                throw RoundSessionReplacementCommandProjectionFailureV1.missingDependency
            }
            return command
        }
        return Projection(source: source, identity: identity, commands: commands)
    }
}

private extension RoundSessionReplacementCommandProjectionV1 {
    struct Original {
        let entry: ReferenceOwnerReplacementSourceV1.Entry
        let mutation: RoundSessionMutationV1
    }

    static func actor(_ value: ActorSnapshotV1, workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        try .init(snapshotID: value.snapshotID, workspaceID: workspaceID,
                  actor: LocalActorReferenceV1(actorReferenceID: value.actor.actorReferenceID,
                                              workspaceID: workspaceID, partyID: value.actor.partyID,
                                              displayName: value.actor.displayName),
                  responsibility: value.responsibility, displayNameAtTime: value.displayNameAtTime,
                  capturedAt: value.capturedAt)
    }
}
