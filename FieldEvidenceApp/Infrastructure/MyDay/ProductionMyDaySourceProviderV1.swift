import Foundation
import SwiftData

enum MyDaySourceReadFailureV1: Error, Equatable {
    case sessionChanged, sourcesChanged, corruptSourceClosure
}

enum MyDayReadinessAssessmentV1: Equatable, Sendable {
    case notAssessed
    case roundManifest(OfflineReadinessManifestV1)
    case unavailable(ProductionRoundReadinessUnavailableV1)

    var readiness: MyDayReadinessV1 {
        switch self {
        case .notAssessed, .unavailable: return .unavailable
        case let .roundManifest(manifest):
            switch manifest.status {
            case .ready: return .ready
            case .blocked: return .blocked
            case .warning, .stale: return .notReady
            }
        }
    }
}

/// Ephemeral exact-source evidence, never a cached access capability.
struct MyDaySourceReadinessAssessmentV1: Equatable, Sendable {
    let reference: MyDayEligibleReferenceV1
    let assessment: MyDayReadinessAssessmentV1
}

/// Derived source facts, not planning or readiness persistence. Packet versions
/// remain separate choices; selecting a plan still requires unique stable keys.
struct MyDayLiveSourceV1: Equatable, Sendable {
    let reference: MyDayEligibleReferenceV1
    let state: MyDaySourceStateV1
    let dueAt: Date?
    let replacementOccurrenceID: OccurrenceIDV1?

    var isSelectable: Bool { MyDaySourceSemanticsV1.isSelectable(state, reference: reference) }
}

/// This value is not an access capability. The composing surface must discard
/// it under the privacy cover and freshly authorize every render/navigation.
struct MyDaySourceSnapshotV1: Sendable {
    let workspaceID: WorkspaceID
    let evaluatedAt: Date
    let sources: [MyDayLiveSourceV1]
    let frontiers: [MyDaySourceFrontierV1]
    let dueQueue: OccurrenceDueQueueStateV1
    let sourceClosureSHA256: String
    let readinessAssessments: [MyDaySourceReadinessAssessmentV1]

    var eligibleReferences: [MyDayEligibleReferenceV1] {
        sources.filter(\.isSelectable).map(\.reference)
    }
}

/// A revocable, generation-bound read entry. It neither conforms to nor exports
/// a permanently authorized synchronous source reader. The concrete gate is
/// mandatory; there is no permissive protocol default or cached permit.
@MainActor final class ProductionMyDaySourceProviderV1 {
    private weak var session: StoreSessionCoordinator?
    private let accessGate: AppAccessGateV1
    private let workspaceID: WorkspaceID
    private let generationID: UUID
    private let uiGenerationToken: UInt64
    private weak var originalWriter: WorkspaceWriterV1?
    private let readinessAuthority: ProductionOfflineReadinessAuthorityV1?

    #if DEBUG
    /// Fault-injection only; cannot supply data, readiness or authorization.
    var afterSourceMaterializationForTesting: (@MainActor () async throws -> Void)?
    #endif

    init(session: StoreSessionCoordinator, accessGate: AppAccessGateV1) {
        self.session = session
        self.accessGate = accessGate
        workspaceID = session.workspaceID
        generationID = session.generationID
        uiGenerationToken = session.uiGenerationToken
        originalWriter = session.workspaceWriter
        readinessAuthority = nil
    }

    init(session: StoreSessionCoordinator, accessGate: AppAccessGateV1,
         readinessAuthority: ProductionOfflineReadinessAuthorityV1) {
        self.session = session; self.accessGate = accessGate
        workspaceID = session.workspaceID; generationID = session.generationID
        uiGenerationToken = session.uiGenerationToken; originalWriter = session.workspaceWriter
        self.readinessAuthority = readinessAuthority
    }

    func snapshot(for plan: MyDayPlanV1? = nil, evaluatedAt: Date) async throws -> MyDaySourceSnapshotV1 {
        let token = try await accessGate.beginContentRead(for: .render)
        try Task.checkCancellation()
        try plan?.validate()
        try MyDayLimitsV1.millisecondInstant(evaluatedAt)
        guard plan.map({ $0.key.workspaceID == workspaceID }) ?? true else {
            throw MyDayFailureV1.wrongWorkspace
        }
        let current = try currentSession()
        let revision = try current.workspaceWriter.currentRevision()
        let closure = try SourceClosure(context: current.modelContext, workspaceID: workspaceID,
                                        includeReadiness: readinessAuthority != nil)
        let sourceResult = try closure.snapshot(workspaceID: workspaceID, plan: plan, evaluatedAt: evaluatedAt)
        var assessments: [MyDaySourceReadinessAssessmentV1] = []
        for source in sourceResult.sources {
            if let readinessAuthority, case .roundSession = source.reference {
                assessments.append(try await readinessAuthority.assess(source.reference))
            } else {
                assessments.append(.init(reference: source.reference, assessment: .notAssessed))
            }
        }
        let frontiers = try sourceResult.frontiers.map { frontier in
            let assessment = assessments.first { $0.reference == frontier.currentReference }
            return try MyDaySourceFrontierV1(membershipID: frontier.membershipID,
                plannedReference: frontier.plannedReference, currentReference: frontier.currentReference,
                state: frontier.state, readiness: assessment?.assessment.readiness ?? .unavailable,
                dueAt: frontier.dueAt, evaluatedAt: frontier.evaluatedAt)
        }
        let result = MyDaySourceSnapshotV1(workspaceID: workspaceID, evaluatedAt: evaluatedAt,
            sources: sourceResult.sources, frontiers: frontiers, dueQueue: sourceResult.dueQueue,
            sourceClosureSHA256: sourceResult.sourceClosureSHA256, readinessAssessments: assessments)
        let completionRoot = try readinessAuthority?.validateCompletionsForPublication(assessments)
        #if DEBUG
        try await afterSourceMaterializationForTesting?()
        #endif
        // Gate validation is an asynchronous publication boundary. A lock or
        // lock/unlock cycle during materialization invalidates this operation.
        try await accessGate.validateContentRead(token, for: .render)
        try Task.checkCancellation()
        try readinessAuthority?.validateStorageForPublication(assessments,
            expectedGenerationRootIdentity: completionRoot)
        let rereadSession = try currentSession()
        guard try rereadSession.workspaceWriter.currentRevision() == revision else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        let reread = try SourceClosure(context: rereadSession.modelContext, workspaceID: workspaceID,
                                      includeReadiness: readinessAuthority != nil)
        guard try reread.sha256() == result.sourceClosureSHA256 else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        return result
    }

    private func currentSession() throws -> StoreSessionCoordinator {
        guard let session, let originalWriter, session.workspaceID == workspaceID,
              session.generationID == generationID, session.uiGenerationToken == uiGenerationToken,
              originalWriter === session.workspaceWriter else {
            throw MyDaySourceReadFailureV1.sessionChanged
        }
        return session
    }

    private struct SourceClosure: Encodable {
        let manifests: [WorkPacketManifestV1]
        let claims: [WorkItemClaimV1]
        let leases: [WorkLeaseV1]
        let releases: [WorkReleaseV1]
        let handoffs: [WorkHandoffV1]
        let rounds: [RoundSessionV1]
        let definitions: [ScheduleDefinitionReleaseV1]
        let occurrences: [OccurrenceHistoryEventV1]
        let drafts: [FieldDraftCheckpointV1]
        let readinessSources: ProductionOfflineReadinessSourceClosureV1?

        @MainActor init(context: ModelContext, workspaceID: WorkspaceID, includeReadiness: Bool) throws {
            guard !context.hasChanges else { throw MyDaySourceReadFailureV1.sourcesChanged }
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
            rounds = try context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { ($0.sessionID.uuidString, $0.revision) < ($1.sessionID.uuidString, $1.revision) }
            definitions = try context.fetch(FetchDescriptor<ScheduleDefinitionReleaseRow>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }
            occurrences = try context.fetch(FetchDescriptor<OccurrenceHistoryEventRow>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
            drafts = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>(predicate: #Predicate { $0.workspaceID == workspace }))
                .map { try $0.value() }.sorted { $0.draftID.uuidString < $1.draftID.uuidString }
            readinessSources = includeReadiness ? try ProductionOfflineReadinessSourceClosureV1(context: context, workspaceID: workspaceID) : nil
        }

        func sha256() throws -> String { try MyDayCanonicalCodecV1.sha256(self) }

        func snapshot(workspaceID: WorkspaceID, plan: MyDayPlanV1?, evaluatedAt: Date) throws -> MyDaySourceSnapshotV1 {
            try validatePacketClosure()
            guard Set(drafts.map(\.draftID)).count == drafts.count else {
                throw MyDaySourceReadFailureV1.corruptSourceClosure
            }
            let due = try DueQueueProjectionV1(workspaceID: workspaceID, evaluatedAt: evaluatedAt,
                definitions: definitions, history: occurrences).recurringRoundState()
            var sources: [MyDayLiveSourceV1] = []
            for manifest in manifests {
                let projection = try WorkPacketProjectionBuilderV1.rebuild(workspaceID: workspaceID,
                    manifest: manifest, claims: claims, leases: leases, releases: releases,
                    handoffs: handoffs, at: evaluatedAt)
                let state: MyDaySourceStateV1
                if projection.items.contains(where: { !$0.exceptions.isEmpty }) {
                    state = .conflicted
                } else if projection.items.allSatisfy({ $0.currentClaim == nil && $0.latestRelease?.reason == .completed }) {
                    state = .completed
                } else if projection.items.contains(where: { item in
                    guard let claim = item.currentClaim else { return false }
                    return releases.contains { $0.item == item.item && $0.reason == .completed && $0.releasedAt <= claim.claimedAt }
                }) {
                    state = .reopened
                } else {
                    state = .active
                }
                sources.append(.init(reference: .workPacket(try .init(manifest)), state: state,
                                     dueAt: nil, replacementOccurrenceID: nil))
            }
            for (sessionID, history) in Dictionary(grouping: rounds, by: \.sessionID) {
                guard let current = try RoundSessionHistoryValidatorV1.validate(history,
                    workspaceID: workspaceID, sessionID: sessionID) else {
                    throw MyDaySourceReadFailureV1.corruptSourceClosure
                }
                let state: MyDaySourceStateV1
                switch current.state {
                case .draft: state = .draft
                case .active: state = .active
                case .paused: state = .paused
                case .completed: state = .completed
                case .archived: state = .archived
                }
                sources.append(.init(reference: .roundSession(workspaceID: workspaceID, sessionID: sessionID,
                    revision: current.revision, sessionSHA256: current.sessionSHA256), state: state,
                    dueAt: nil, replacementOccurrenceID: nil))
            }
            for events in Dictionary(grouping: occurrences, by: \.occurrenceID).values {
                guard let current = events.max(by: { $0.revision < $1.revision }),
                      let item = due.items.first(where: { $0.entry.occurrenceID == current.occurrenceID }) else {
                    throw MyDaySourceReadFailureV1.corruptSourceClosure
                }
                let state: MyDaySourceStateV1
                if current.exception?.kind == .retiredForRuleChange { state = .ruleRetired }
                else {
                    switch item.reason {
                    case .explicitlyMissed: state = .missed
                    case .explicitlySkipped: state = .skipped
                    case .explicitlyCancelled: state = .cancelled
                    case .completed: state = .completed
                    default: state = .active
                    }
                }
                sources.append(.init(reference: .scheduleOccurrence(try .init(event: current),
                    sourceEventSHA256: current.eventSHA256), state: state,
                    dueAt: item.entry.effectiveDueAtUTC,
                    replacementOccurrenceID: current.exception?.replacementOccurrenceID))
            }
            for checkpoint in drafts {
                let state: MyDaySourceStateV1
                switch checkpoint.state {
                case .active: state = .draft
                case .committing: state = .committing
                case .conflicted: state = .conflicted
                case .recoveryRequired: state = .recoveryRequired
                case .committed: state = .committed
                case .discardPending: state = .discardPending
                case .discarded: state = .discarded
                }
                sources.append(.init(reference: .resumableDraft(workspaceID: workspaceID,
                    draftID: checkpoint.draftID, revision: checkpoint.draftRevision,
                    checkpointSHA256: checkpoint.checkpointSHA256, anchor: checkpoint.resumeAnchor),
                    state: state, dueAt: nil, replacementOccurrenceID: nil))
            }
            sources.sort { ($0.reference.stableKey, $0.reference.sourceRevision, $0.reference.sourceSHA256)
                < ($1.reference.stableKey, $1.reference.sourceRevision, $1.reference.sourceSHA256) }
            let frontiers = try (plan?.items ?? []).map { item -> MyDaySourceFrontierV1 in
                let matching: [MyDayLiveSourceV1]
                if case let .workPacket(reference) = item.reference {
                    matching = sources.filter {
                        if case let .workPacket(current) = $0.reference { return current.manifestID == reference.manifestID }
                        return false
                    }
                } else { matching = sources.filter { $0.reference.stableKey == item.reference.stableKey } }
                guard matching.count <= 1 else { throw MyDaySourceReadFailureV1.corruptSourceClosure }
                let current = matching.first
                return try .init(membershipID: item.membershipID, plannedReference: item.reference,
                    currentReference: current?.reference, state: current?.state ?? .missing,
                    readiness: .unavailable, dueAt: current?.dueAt, evaluatedAt: evaluatedAt)
            }
            return .init(workspaceID: workspaceID, evaluatedAt: evaluatedAt, sources: sources,
                frontiers: frontiers, dueQueue: due, sourceClosureSHA256: try sha256(),
                readinessAssessments: sources.map { .init(reference: $0.reference, assessment: .notAssessed) })
        }

        private func validatePacketClosure() throws {
            guard Set(manifests.map(\.manifestID)).count == manifests.count,
                  Set(manifests.map { "\($0.packetID)|\($0.packetVersion)" }).count == manifests.count,
                  Set(claims.map(\.claimID)).count == claims.count,
                  Set(leases.map(\.leaseID)).count == leases.count,
                  Set(releases.map(\.releaseID)).count == releases.count,
                  Set(handoffs.map(\.handoffID)).count == handoffs.count else {
                throw MyDaySourceReadFailureV1.corruptSourceClosure
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
                throw MyDaySourceReadFailureV1.corruptSourceClosure
            }
        }
    }
}
