import Foundation

enum ReferenceOwnerReplacementCommandPlanFailureV1: Error, Equatable {
    case invalidSource, collision, missingDependency, invalidOrder, invalidFrontier
}

/// Proves one source-ordered Work/Round/Schedule command partition before receipt
/// emission. External target producers remain supplied, unsealed obligations.
/// This value never installs history or grants destination operational authority.
enum ReferenceOwnerReplacementCommandPlanV1 {
    enum Reason: String, Equatable, Sendable {
        case semanticReference, causation, reversal
    }

    struct Dependency: Equatable, Sendable {
        let sourceWorkspaceID: WorkspaceID
        let sourceMutationID: MutationIDV1
        let targetWorkspaceID: WorkspaceID
        let targetMutationID: MutationIDV1
        let reasons: [Reason]

        fileprivate init(sourceWorkspaceID: WorkspaceID, sourceMutationID: MutationIDV1,
                         targetWorkspaceID: WorkspaceID, targetMutationID: MutationIDV1,
                         reasons: [Reason]) {
            self.sourceWorkspaceID = sourceWorkspaceID; self.sourceMutationID = sourceMutationID
            self.targetWorkspaceID = targetWorkspaceID; self.targetMutationID = targetMutationID
            self.reasons = reasons
        }
    }

    enum Payload: Equatable, Sendable {
        case workPacket(WorkPacketReplacementCommandProjectionV1.Command)
        case roundSession(RoundSessionReplacementCommandProjectionV1.Command)
        case schedule(ScheduleReplacementCommandProjectionV1.Command)

        var sourceEntry: ReferenceOwnerReplacementSourceV1.Entry {
            switch self {
            case let .workPacket(value): return value.source
            case let .roundSession(value): return value.source
            case let .schedule(value): return value.sourceEntry
            }
        }

        var targetCommand: WorkspaceCommandV1 {
            switch self {
            case let .workPacket(value): return .applyWorkPacket(value.mutation)
            case let .roundSession(value): return .applyRoundSession(value.mutation)
            case let .schedule(value): return .applySchedule(value.mutation)
            }
        }

        var targetMutationID: MutationIDV1 {
            switch self {
            case let .workPacket(value): return value.mutation.mutationID
            case let .roundSession(value): return value.mutation.mutationID
            case let .schedule(value): return value.mutation.mutationID
            }
        }

        var postImages: [MutationPostImageV1] {
            switch self {
            case let .workPacket(value): return [value.postImage]
            case let .roundSession(value): return [value.postImage]
            case let .schedule(value): return value.postImages
            }
        }

        fileprivate var sourceDependencies: [MutationIDV1] {
            switch self {
            case let .workPacket(value): return value.sourceDependencyMutationIDs
            case let .roundSession(value): return value.sourceDependencyMutationIDs
            case let .schedule(value): return value.sourceDependencyMutationIDs
            }
        }

        fileprivate var targetDependencies: [MutationIDV1] {
            switch self {
            case let .workPacket(value): return value.targetDependencyMutationIDs
            case let .roundSession(value): return value.targetDependencyMutationIDs
            case let .schedule(value): return value.targetDependencyMutationIDs
            }
        }
    }

    struct Node: Equatable, Sendable {
        let payload: Payload
        let dependencies: [Dependency]
        let expectedEntityRevisions: [WorkspaceEntityRevisionV1]
        let resultingEntityRevisions: [WorkspaceEntityRevisionV1]
        var sourceEntry: ReferenceOwnerReplacementSourceV1.Entry { payload.sourceEntry }
        var targetCommand: WorkspaceCommandV1 { payload.targetCommand }
        var targetMutationID: MutationIDV1 { payload.targetMutationID }
        var postImages: [MutationPostImageV1] { payload.postImages }

        fileprivate init(payload: Payload, dependencies: [Dependency],
                         expectedEntityRevisions: [WorkspaceEntityRevisionV1],
                         resultingEntityRevisions: [WorkspaceEntityRevisionV1]) {
            self.payload = payload; self.dependencies = dependencies
            self.expectedEntityRevisions = expectedEntityRevisions
            self.resultingEntityRevisions = resultingEntityRevisions
        }
    }

    /// Only the source record is authenticated historical production. The full
    /// supplied target command is intrinsically valid and consistently bound;
    /// its owner transformation, frontier and receipt remain unproven here.
    struct ExternalProducerObligation: Equatable, Sendable {
        let sourceRecord: MutationHistoryReceiptRecordV1
        let sourceEnvelope: MutationEnvelopeV1
        let sourceReceipt: MutationReceiptV1
        let targetCommand: WorkspaceCommandV1
        let targetMutationID: MutationIDV1

        fileprivate init(sourceRecord: MutationHistoryReceiptRecordV1,
                         sourceEnvelope: MutationEnvelopeV1, sourceReceipt: MutationReceiptV1,
                         targetCommand: WorkspaceCommandV1,
                         targetMutationID: MutationIDV1) {
            self.sourceRecord = sourceRecord; self.sourceEnvelope = sourceEnvelope
            self.sourceReceipt = sourceReceipt; self.targetCommand = targetCommand
            self.targetMutationID = targetMutationID
        }
    }

    struct Plan: Equatable, Sendable {
        let source: ReferenceOwnerReplacementSourceV1.Source
        let identity: RestoreIdentityV1
        let workPacketProjection: WorkPacketReplacementCommandProjectionV1.Projection
        let roundProjection: RoundSessionReplacementCommandProjectionV1.Projection
        let scheduleProjection: ScheduleReplacementCommandProjectionV1.Projection
        let definitionBindings: [ScheduleReplacementCommandProjectionV1.DefinitionBinding]
        let packageBindings: [ScheduleReplacementCommandProjectionV1.PackageBinding]
        let nodes: [Node]
        let externalProducerObligations: [ExternalProducerObligation]
        let resultingEntityRevisions: [WorkspaceEntityRevisionV1]
        let nonselectedEntries: [ReferenceOwnerReplacementSourceV1.Entry]

        fileprivate init(source: ReferenceOwnerReplacementSourceV1.Source, identity: RestoreIdentityV1,
                         work: WorkPacketReplacementCommandProjectionV1.Projection,
                         round: RoundSessionReplacementCommandProjectionV1.Projection,
                         schedule: ScheduleReplacementCommandProjectionV1.Projection,
                         definitions: [ScheduleReplacementCommandProjectionV1.DefinitionBinding],
                         packages: [ScheduleReplacementCommandProjectionV1.PackageBinding],
                         nodes: [Node], external: [ExternalProducerObligation],
                         frontier: [WorkspaceEntityRevisionV1]) {
            self.source = source; self.identity = identity
            workPacketProjection = work; roundProjection = round; scheduleProjection = schedule
            definitionBindings = definitions; packageBindings = packages; self.nodes = nodes
            externalProducerObligations = external; resultingEntityRevisions = frontier
            nonselectedEntries = source.entries.filter { !Self.isSelected($0.family) }
        }

        fileprivate static func isSelected(_ family: ReferenceOwnerReplacementSourceV1.Family) -> Bool {
            switch family {
            case .workPacket, .roundSession, .schedule: return true
            case .guidedSurvey, .fieldDraft: return false
            }
        }
    }

    static func plan(source: ReferenceOwnerReplacementSourceV1.Source, identity: RestoreIdentityV1,
                     definitionBindings: [ScheduleReplacementCommandProjectionV1.DefinitionBinding],
                     packageBindings: [ScheduleReplacementCommandProjectionV1.PackageBinding]) throws -> Plan {
        let work = try WorkPacketReplacementCommandProjectionV1.project(source: source, identity: identity)
        let round = try RoundSessionReplacementCommandProjectionV1.project(source: source, identity: identity)
        let schedule = try ScheduleReplacementCommandProjectionV1.project(
            source: source, identity: identity, definitionBindings: definitionBindings,
            packageBindings: packageBindings, workPacketProjection: work, roundProjection: round)
        let payloads = work.commands.map(Payload.workPacket)
            + round.commands.map(Payload.roundSession) + schedule.commands.map(Payload.schedule)
        let selected = source.entries.filter { Plan.isSelected($0.family) }
        guard payloads.count == selected.count else { throw Failure.invalidSource }
        var selectedByKey: [Key: ReferenceOwnerReplacementSourceV1.Entry] = [:]
        for entry in selected {
            guard selectedByKey.updateValue(entry, forKey: Key(entry.envelope)) == nil else {
                throw Failure.collision
            }
        }
        var payloadByKey: [Key: Payload] = [:]
        for payload in payloads {
            let entry = payload.sourceEntry
            guard entry.envelope.workspaceID == source.workspaceID,
                  selectedByKey[Key(entry.envelope)] == entry,
                  payloadByKey.updateValue(payload, forKey: Key(entry.envelope)) == nil else {
                throw Failure.collision
            }
        }
        guard Set(selected.map { Key($0.envelope) }) == Set(payloadByKey.keys) else {
            throw Failure.invalidSource
        }

        let originals = try source.history.receipts.map(Original.init)
        let originalIDs = Set(originals.map { $0.envelope.mutationID })
        let sourceOriginals = originals.filter { $0.envelope.workspaceID == source.workspaceID }
        let targetWorkspace = WorkspaceID(rawValue: identity.targetPointer.workspaceID)
        var externalByKey: [Key: ExternalProducerObligation] = [:]
        for binding in definitionBindings {
            guard let pair = binding.producer else { continue }
            let original = try originalProducer(.applySurveyDefinition(pair.source),
                mutationID: pair.source.mutationID, source: source, originals: sourceOriginals)
            _ = try SurveyDefinitionMutationReceiptV1(mutation: pair.source, mutationReceipt: original.receipt)
            try pair.target.validate()
            guard pair.target.workspaceID == targetWorkspace else { throw Failure.invalidSource }
            try addExternal(.init(sourceRecord: original.record, sourceEnvelope: original.envelope,
                sourceReceipt: original.receipt, targetCommand: .applySurveyDefinition(pair.target),
                targetMutationID: pair.target.mutationID), to: &externalByKey)
        }
        for binding in packageBindings {
            for pair in binding.producers {
                let original = try originalProducer(.applyPackagePromotion(pair.source),
                    mutationID: pair.source.mutationID, source: source, originals: sourceOriginals)
                _ = try PackagePromotionMutationReceiptV1(mutation: pair.source, mutationReceipt: original.receipt)
                try pair.target.validate()
                guard pair.target.workspaceID == targetWorkspace else { throw Failure.invalidSource }
                try addExternal(.init(sourceRecord: original.record, sourceEnvelope: original.envelope,
                    sourceReceipt: original.receipt, targetCommand: .applyPackagePromotion(pair.target),
                    targetMutationID: pair.target.mutationID), to: &externalByKey)
            }
        }

        var targetByKey: [Key: MutationIDV1] = [:]
        var sourceByTarget: [MutationIDV1: Key] = [:]
        for (key, payload) in payloadByKey {
            try bind(key, target: payload.targetMutationID, originals: originalIDs,
                     targets: &targetByKey, sources: &sourceByTarget)
        }
        for (key, external) in externalByKey {
            guard payloadByKey[key] == nil else { throw Failure.collision }
            try bind(key, target: external.targetMutationID, originals: originalIDs,
                     targets: &targetByKey, sources: &sourceByTarget)
        }

        var emittedKeys = Set<Key>()
        var consumedExternal = Set<Key>()
        var frontier: [WorkspaceEntityIdentityV1: UInt64] = [:]
        var nodes: [Node] = []
        for entry in selected {
            let key = Key(entry.envelope)
            guard let payload = payloadByKey[key], payload.sourceEntry == entry else {
                throw Failure.invalidSource
            }
            let sourceIDs = payload.sourceDependencies, targetIDs = payload.targetDependencies
            guard sourceIDs.count == targetIDs.count, Set(sourceIDs).count == sourceIDs.count,
                  Set(targetIDs).count == targetIDs.count else { throw Failure.collision }
            var reasons: [Key: [Reason]] = [:]
            for (sourceID, targetID) in zip(sourceIDs, targetIDs) {
                let dependency = Key(workspaceID: source.workspaceID, mutationID: sourceID)
                guard targetByKey[dependency] == targetID else { throw Failure.missingDependency }
                reasons[dependency] = [.semanticReference]
            }
            if let causation = entry.envelope.causationMutationID {
                reasons[Key(workspaceID: source.workspaceID, mutationID: causation), default: []].append(.causation)
            }
            if let reversal = entry.receipt.reversesMutationID {
                reasons[Key(workspaceID: source.workspaceID, mutationID: reversal), default: []].append(.reversal)
            }
            var dependencies: [Dependency] = []
            for dependency in reasons.keys.sorted(by: keyLess) {
                guard dependency != key, let target = targetByKey[dependency] else {
                    throw Failure.missingDependency
                }
                let producerReceipt: MutationReceiptV1
                if let selectedProducer = payloadByKey[dependency] {
                    guard emittedKeys.contains(dependency) else { throw Failure.invalidOrder }
                    producerReceipt = selectedProducer.sourceEntry.receipt
                } else if let external = externalByKey[dependency] {
                    producerReceipt = external.sourceReceipt; consumedExternal.insert(dependency)
                } else { throw Failure.missingDependency }
                guard producerReceipt.resultingRevision.workspaceRevision
                        < entry.receipt.resultingRevision.workspaceRevision else { throw Failure.invalidOrder }
                dependencies.append(.init(sourceWorkspaceID: dependency.workspaceID,
                    sourceMutationID: dependency.mutationID, targetWorkspaceID: targetWorkspace,
                    targetMutationID: target, reasons: reasons[dependency]!.sorted { $0.rawValue < $1.rawValue }))
            }
            let expected = try expectations(payload)
            guard Set(expected.map(\.identity)).count == expected.count,
                  expected.allSatisfy({ frontier[$0.identity, default: 0] == $0.revision }) else {
                throw Failure.invalidFrontier
            }
            let updates = try atomicUpdates(payload)
            for (identity, revision) in updates {
                guard frontier[identity, default: 0] < revision else { throw Failure.invalidFrontier }
            }
            for (identity, revision) in updates { frontier[identity] = revision }
            guard emittedKeys.insert(key).inserted else { throw Failure.collision }
            nodes.append(.init(payload: payload, dependencies: dependencies,
                expectedEntityRevisions: expected, resultingEntityRevisions: rows(frontier)))
        }
        guard emittedKeys == Set(payloadByKey.keys) else { throw Failure.invalidSource }
        let obligations = consumedExternal.sorted { lhs, rhs in
            let left = externalByKey[lhs]!.sourceReceipt, right = externalByKey[rhs]!.sourceReceipt
            if left.resultingRevision.workspaceRevision != right.resultingRevision.workspaceRevision {
                return left.resultingRevision.workspaceRevision < right.resultingRevision.workspaceRevision
            }
            return keyLess(lhs, rhs)
        }.map { externalByKey[$0]! }
        return Plan(source: source, identity: identity, work: work, round: round, schedule: schedule,
            definitions: definitionBindings, packages: packageBindings, nodes: nodes,
            external: obligations, frontier: rows(frontier))
    }
}

private extension ReferenceOwnerReplacementCommandPlanV1 {
    typealias Failure = ReferenceOwnerReplacementCommandPlanFailureV1

    struct Key: Hashable {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
        init(workspaceID: WorkspaceID, mutationID: MutationIDV1) {
            self.workspaceID = workspaceID; self.mutationID = mutationID
        }
        init(_ envelope: MutationEnvelopeV1) {
            self.init(workspaceID: envelope.workspaceID, mutationID: envelope.mutationID)
        }
    }

    struct Original {
        let record: MutationHistoryReceiptRecordV1
        let envelope: MutationEnvelopeV1
        let receipt: MutationReceiptV1
        init(_ record: MutationHistoryReceiptRecordV1) throws {
            self.record = record
            envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
        }
    }

    static func keyLess(_ lhs: Key, _ rhs: Key) -> Bool {
        if lhs.workspaceID != rhs.workspaceID { return lhs.workspaceID.rawValue.uuidString < rhs.workspaceID.rawValue.uuidString }
        return lhs.mutationID.rawValue.uuidString < rhs.mutationID.rawValue.uuidString
    }

    static func rows(_ frontier: [WorkspaceEntityIdentityV1: UInt64]) -> [WorkspaceEntityRevisionV1] {
        frontier.keys.sorted { $0.stableKey < $1.stableKey }.map {
            WorkspaceEntityRevisionV1(identity: $0, revision: frontier[$0]!)
        }
    }

    static func originalProducer(_ command: WorkspaceCommandV1, mutationID: MutationIDV1,
                                 source: ReferenceOwnerReplacementSourceV1.Source,
                                 originals: [Original]) throws -> Original {
        let matches = originals.filter { $0.envelope.mutationID == mutationID }
        guard matches.count == 1, let original = matches.first,
              original.envelope.command == command,
              original.receipt.envelopeSHA256 == (try original.envelope.canonicalSHA256()),
              original.receipt.identity.workspaceID == source.workspaceID,
              original.receipt.mutationID == mutationID,
              original.receipt.commandBodySHA256 == original.envelope.commandBodySHA256,
              original.receipt.expectedRevision == original.envelope.expectedRevision,
              !source.history.quarantines.contains(where: {
                  $0.workspaceID == source.workspaceID && $0.mutationID == mutationID.rawValue
              }) else { throw Failure.invalidSource }
        return original
    }

    static func addExternal(_ value: ExternalProducerObligation,
                            to values: inout [Key: ExternalProducerObligation]) throws {
        let key = Key(value.sourceEnvelope)
        if let prior = values[key] {
            guard prior == value else { throw Failure.collision }
        } else { values[key] = value }
    }

    static func bind(_ source: Key, target: MutationIDV1, originals: Set<MutationIDV1>,
                     targets: inout [Key: MutationIDV1], sources: inout [MutationIDV1: Key]) throws {
        guard !originals.contains(target), targets[source] == nil, sources[target] == nil else {
            throw Failure.collision
        }
        targets[source] = target; sources[target] = source
    }

    static func expectations(_ payload: Payload) throws -> [WorkspaceEntityRevisionV1] {
        switch payload {
        case let .workPacket(value):
            try value.mutation.validate()
            return [try WorkspaceEntityRevisionV1(identity: value.mutation.concurrencyIdentity,
                revision: value.mutation.expectedRevision)]
        case let .roundSession(value):
            try value.mutation.validate()
            return [try WorkspaceEntityRevisionV1(identity: value.mutation.concurrencyIdentity,
                revision: value.mutation.expectedRevision)]
        case let .schedule(value):
            try value.mutation.validate()
            return try value.mutation.concurrencyIdentities.map {
                WorkspaceEntityRevisionV1(identity: $0, revision: try value.mutation.expectedRevision(for: $0))
            }
        }
    }

    static func atomicUpdates(_ payload: Payload) throws -> [WorkspaceEntityIdentityV1: UInt64] {
        let actual: [MutationPostImageV1]
        switch payload {
        case let .workPacket(value): actual = [try value.mutation.postImage.mutationPostImage]
        case let .roundSession(value): actual = [try value.mutation.mutationPostImage]
        case let .schedule(value): actual = try value.mutation.mutationPostImages
        }
        guard actual == payload.postImages,
              Set(try actual.map { try $0.identity }).count == actual.count else { throw Failure.invalidSource }
        var updates: [WorkspaceEntityIdentityV1: UInt64] = [:]
        for image in actual {
            for identity in try [image.identity, image.concurrencyIdentity] {
                if let prior = updates[identity], prior != image.revision { throw Failure.invalidFrontier }
                updates[identity] = image.revision
            }
        }
        return updates
    }
}
