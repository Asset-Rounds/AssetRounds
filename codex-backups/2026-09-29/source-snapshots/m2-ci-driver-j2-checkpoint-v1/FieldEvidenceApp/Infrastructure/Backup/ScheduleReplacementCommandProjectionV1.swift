import Foundation

enum ScheduleReplacementCommandProjectionFailureV1: Error, Equatable {
    case invalidIdentity, invalidSource, collision, missingDependency
}

/// Immutable historical commands before the global replacement sequencer seals
/// receipts. This projection never reads current rows or writes a workspace.
enum ScheduleReplacementCommandProjectionV1 {
    struct DefinitionProducerPair: Equatable, Sendable {
        let source: SurveyDefinitionMutationV1
        let target: SurveyDefinitionMutationV1
    }
    struct DefinitionBinding: Equatable, Sendable {
        let source: SurveyDefinitionReleaseV1
        let target: SurveyDefinitionReleaseV1
        let producer: DefinitionProducerPair?
    }
    struct PackageProducerPair: Equatable, Sendable {
        let source: PackagePromotionMutationV1
        let target: PackagePromotionMutationV1
    }
    struct PackageBinding: Equatable, Sendable {
        let source: InspectionPackageReleaseV1
        let target: InspectionPackageReleaseV1
        let producers: [PackageProducerPair]
    }
    struct Command: Equatable, Sendable {
        let sourceEntry: ReferenceOwnerReplacementSourceV1.Entry
        let mutation: ScheduleMutationV1
        let postImages: [MutationPostImageV1]
        let sourceDependencyMutationIDs: [MutationIDV1]
        let targetDependencyMutationIDs: [MutationIDV1]

        fileprivate init(sourceEntry: ReferenceOwnerReplacementSourceV1.Entry,
                         mutation: ScheduleMutationV1,
                         dependencies: [MutationIDV1: MutationIDV1]) throws {
            self.sourceEntry = sourceEntry; self.mutation = mutation
            postImages = try mutation.mutationPostImages
            let keys = dependencies.keys.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            sourceDependencyMutationIDs = keys
            targetDependencyMutationIDs = try keys.map {
                guard let target = dependencies[$0] else { throw Failure.invalidSource }
                return target
            }
        }
    }
    fileprivate struct Pair<Value: Equatable & Sendable>: Equatable, Sendable {
        let source: Value
        let target: Value
    }
    struct Projection: Equatable, Sendable {
        let source: ReferenceOwnerReplacementSourceV1.Source
        let identity: RestoreIdentityV1
        let commands: [Command]
        fileprivate let releases: [Pair<ScheduleDefinitionReleaseV1>]
        fileprivate let calendars: [Pair<ExceptionCalendarReleaseV1>]
        fileprivate let overrides: [Pair<ScheduleOverrideEventV1>]
        fileprivate let events: [Pair<OccurrenceHistoryEventV1>]

        fileprivate init(source: ReferenceOwnerReplacementSourceV1.Source,
                         identity: RestoreIdentityV1, commands: [Command],
                         releases: [Pair<ScheduleDefinitionReleaseV1>],
                         calendars: [Pair<ExceptionCalendarReleaseV1>],
                         overrides: [Pair<ScheduleOverrideEventV1>],
                         events: [Pair<OccurrenceHistoryEventV1>]) {
            self.source = source; self.identity = identity; self.commands = commands
            self.releases = releases; self.calendars = calendars
            self.overrides = overrides; self.events = events
        }
        func targetRelease(for reference: ScheduleDefinitionReleaseReferenceV1) throws -> ScheduleDefinitionReleaseV1 {
            try reference.validate()
            return try Self.one(releases.filter { try ScheduleDefinitionReleaseReferenceV1($0.source) == reference }).target
        }
        func targetCalendar(for reference: ExceptionCalendarReleaseReferenceV1) throws -> ExceptionCalendarReleaseV1 {
            try reference.validate()
            return try Self.one(calendars.filter { $0.source.reference == reference }).target
        }
        func targetOverride(for reference: ScheduleOverrideEventReferenceV1) throws -> ScheduleOverrideEventV1 {
            try reference.validate()
            return try Self.one(overrides.filter { $0.source.reference == reference }).target
        }
        func targetEvent(for event: OccurrenceHistoryEventV1) throws -> OccurrenceHistoryEventV1 {
            try event.validateIntrinsic()
            return try Self.one(events.filter { $0.source == event }).target
        }
        func targetOccurrence(for anchor: C34OccurrenceNavigationAnchorV1,
                              eventSHA256: String) throws -> MyDayEligibleReferenceV1 {
            try anchor.validate(); try ScheduleLimitsV1.digest(eventSHA256)
            let pair = try Self.one(events.filter {
                try $0.source.eventSHA256 == eventSHA256 && C34OccurrenceNavigationAnchorV1(event: $0.source) == anchor
            })
            return try .scheduleOccurrence(C34OccurrenceNavigationAnchorV1(event: pair.target),
                                            sourceEventSHA256: pair.target.eventSHA256)
        }
        private static func one<T>(_ values: [T]) throws -> T {
            guard values.count == 1 else { throw Failure.missingDependency }
            return values[0]
        }
    }

    static func project(source: ReferenceOwnerReplacementSourceV1.Source,
                        identity: RestoreIdentityV1,
                        definitionBindings: [DefinitionBinding], packageBindings: [PackageBinding],
                        workPacketProjection: WorkPacketReplacementCommandProjectionV1.Projection,
                        roundProjection: RoundSessionReplacementCommandProjectionV1.Projection) throws -> Projection {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard identity.mode == .replaceExisting,
              source.workspaceID.rawValue == identity.source.workspaceID,
              source.workspaceID.rawValue != zero,
              identity.targetPointer.workspaceID == identity.oldPointer.workspaceID,
              identity.targetPointer.workspaceID != zero,
              identity.targetPointer.generationID != zero,
              identity.targetPointer.generationID != identity.oldPointer.generationID,
              workPacketProjection.source == source, workPacketProjection.identity == identity,
              roundProjection.source == source, roundProjection.identity == identity else {
            throw Failure.invalidIdentity
        }
        return try Engine(source: source, identity: identity, definitions: definitionBindings,
                          packages: packageBindings, work: workPacketProjection, round: roundProjection).project()
    }
}

private extension ScheduleReplacementCommandProjectionV1 {
    typealias Failure = ScheduleReplacementCommandProjectionFailureV1
    struct Original {
        let entry: ReferenceOwnerReplacementSourceV1.Entry
        let mutation: ScheduleMutationV1
    }
    struct OccurrenceKey: Hashable {
        let schedule: UUID
        let namespace: UUID
        let occurrence: OccurrenceIDV1
        init(_ reference: ScheduleDefinitionReleaseReferenceV1, _ occurrence: OccurrenceIDV1) {
            schedule = reference.scheduleDefinitionID; namespace = reference.occurrenceIdentityNamespaceID
            self.occurrence = occurrence
        }
    }
    final class Engine {
        let source: ReferenceOwnerReplacementSourceV1.Source
        let identity: RestoreIdentityV1
        let workspace: WorkspaceID
        let definitions: [DefinitionBinding]
        let packages: [PackageBinding]
        let work: WorkPacketReplacementCommandProjectionV1.Projection
        let round: RoundSessionReplacementCommandProjectionV1.Projection
        var originals: [Original] = []
        var nodes: [MutationIDV1: Original] = [:]
        var releaseOwners: [UUID: ScheduleDefinitionReleaseV1] = [:]
        var calendarOwners: [UUID: ExceptionCalendarReleaseV1] = [:]
        var overrideOwners: [UUID: ScheduleOverrideEventV1] = [:]
        var eventOwners: [UUID: OccurrenceHistoryEventV1] = [:]
        var identities: [OccurrenceKey: OccurrenceHistoryEventV1] = [:]
        var addedIdentities: [OccurrenceKey: ScheduleOverrideEventV1] = [:]
        var mappedIdentities: [OccurrenceKey: OccurrenceIDV1] = [:]
        var visitingIdentities = Set<OccurrenceKey>()
        var mappedIDs: [MutationIDV1: MutationIDV1] = [:]
        var reverseIDs: [MutationIDV1: MutationIDV1] = [:]
        var allSourceIDs = Set<MutationIDV1>()
        var revisions: [MutationIDV1: UInt64] = [:]
        var definitionProducers: [SurveyDefinitionMutationV1] = []
        var packageProducers: [PackagePromotionMutationV1] = []
        var consumedDefinitions = Set<SurveyDefinitionReleaseReferenceV1>()
        var consumedPackages = Set<String>()
        var commands: [MutationIDV1: Command] = [:]
        var stack: [MutationIDV1] = []
        var dependencies: [MutationIDV1: [MutationIDV1: MutationIDV1]] = [:]
        var releases: [UUID: Pair<ScheduleDefinitionReleaseV1>] = [:]
        var calendars: [UUID: Pair<ExceptionCalendarReleaseV1>] = [:]
        var overrides: [UUID: Pair<ScheduleOverrideEventV1>] = [:]
        var events: [UUID: Pair<OccurrenceHistoryEventV1>] = [:]

        init(source: ReferenceOwnerReplacementSourceV1.Source, identity: RestoreIdentityV1,
             definitions: [DefinitionBinding], packages: [PackageBinding],
             work: WorkPacketReplacementCommandProjectionV1.Projection,
             round: RoundSessionReplacementCommandProjectionV1.Projection) {
            self.source = source; self.identity = identity
            workspace = WorkspaceID(rawValue: identity.targetPointer.workspaceID)
            self.definitions = definitions; self.packages = packages; self.work = work; self.round = round
        }

        func project() throws -> Projection {
            try index()
            try validateBindings()
            try ScheduleLifecycleClosureV1(definitions: Array(releaseOwners.values), history: Array(eventOwners.values)).validate()
            try validateAuxiliary(calendars: Array(calendarOwners.values), overrides: Array(overrideOwners.values))
            for original in originals { _ = try build(original.mutation.mutationID) }
            let ordered = try originals.map { original -> Command in
                guard let value = commands[original.mutation.mutationID] else { throw Failure.missingDependency }
                return value
            }
            guard releases.count == releaseOwners.count, calendars.count == calendarOwners.count,
                  overrides.count == overrideOwners.count, events.count == eventOwners.count,
                  consumedDefinitions == (try Set(definitions.map { try SurveyDefinitionReleaseReferenceV1($0.source) })),
                  consumedPackages == Set(packages.map { $0.source.packageReleaseID }) else { throw Failure.invalidSource }
            try ScheduleLifecycleClosureV1(definitions: releases.values.map(\.target), history: events.values.map(\.target)).validate()
            try validateAuxiliary(calendars: calendars.values.map(\.target), overrides: overrides.values.map(\.target))
            let orderedReleases = releases.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { releases[$0] }
            let orderedCalendars = calendars.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { calendars[$0] }
            let orderedOverrides = overrides.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { overrides[$0] }
            let orderedEvents = events.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { events[$0] }
            return Projection(source: source, identity: identity, commands: ordered,
                              releases: orderedReleases, calendars: orderedCalendars,
                              overrides: orderedOverrides, events: orderedEvents)
        }

        func register(_ sourceID: MutationIDV1, _ targetID: MutationIDV1) throws {
            guard !allSourceIDs.contains(targetID),
                  mappedIDs[sourceID].map({ $0 == targetID }) ?? true,
                  reverseIDs[targetID].map({ $0 == sourceID }) ?? true else { throw Failure.collision }
            mappedIDs[sourceID] = targetID; reverseIDs[targetID] = sourceID
        }

        func validateAuxiliary(calendars: [ExceptionCalendarReleaseV1], overrides: [ScheduleOverrideEventV1]) throws {
            for group in Dictionary(grouping: calendars, by: \.calendarID).values {
                let ordered = group.sorted { $0.revision < $1.revision }
                guard ordered.first?.revision == 1 else { throw Failure.invalidSource }
                try ordered.forEach { try $0.validate() }
                for index in 1..<ordered.count { try ordered[index].validateSuccessor(of: ordered[index - 1]) }
            }
            _ = try ScheduleOverridePrecedenceV1.activeEvents(overrides)
            let predecessors = overrides.compactMap(\.supersedesEventID)
            guard Set(predecessors).count == predecessors.count else { throw Failure.invalidSource }
        }

        func depend(_ sourceID: MutationIDV1, _ targetID: MutationIDV1) throws {
            try register(sourceID, targetID)
            guard let current = stack.last, current != sourceID,
                  let producerRevision = revisions[sourceID], let consumerRevision = revisions[current],
                  producerRevision < consumerRevision else { throw Failure.invalidSource }
            var pairs = dependencies[current] ?? [:]
            guard pairs[sourceID].map({ $0 == targetID }) ?? true else { throw Failure.collision }
            pairs[sourceID] = targetID; dependencies[current] = pairs
        }

        func require(_ id: MutationIDV1) throws {
            let command = try build(id)
            try depend(id, command.mutation.mutationID)
        }

        func release(_ value: ScheduleDefinitionReleaseV1) throws -> ScheduleDefinitionReleaseV1 {
            guard releaseOwners[value.releaseID] == value else { throw Failure.missingDependency }
            try require(value.mutationID)
            // Embedded historical releases consume the same exact external
            // values, including every promotion preceding this consumer.
            _ = try workDefinition(value.workDefinition)
            guard let pair = releases[value.releaseID] else { throw Failure.missingDependency }
            return pair.target
        }
        func release(_ reference: ScheduleDefinitionReleaseReferenceV1) throws -> ScheduleDefinitionReleaseV1 {
            guard let value = releaseOwners[reference.releaseID],
                  try ScheduleDefinitionReleaseReferenceV1(value) == reference else { throw Failure.missingDependency }
            return try release(value)
        }
        func calendar(_ value: ExceptionCalendarReleaseV1) throws -> ExceptionCalendarReleaseV1 {
            guard calendarOwners[value.releaseID] == value else { throw Failure.missingDependency }
            try require(value.mutationID)
            guard let pair = calendars[value.releaseID] else { throw Failure.missingDependency }
            return pair.target
        }
        func calendar(_ reference: ExceptionCalendarReleaseReferenceV1) throws -> ExceptionCalendarReleaseV1 {
            guard let value = calendarOwners[reference.releaseID], value.reference == reference else { throw Failure.missingDependency }
            return try calendar(value)
        }
        func mappedOverride(_ value: ScheduleOverrideEventV1) throws -> ScheduleOverrideEventV1 {
            guard overrideOwners[value.eventID] == value else { throw Failure.missingDependency }
            try require(value.mutationID)
            guard let pair = overrides[value.eventID] else { throw Failure.missingDependency }
            return pair.target
        }
        func event(_ value: OccurrenceHistoryEventV1) throws -> OccurrenceHistoryEventV1 {
            guard eventOwners[value.eventID] == value else { throw Failure.missingDependency }
            try require(value.mutationID)
            guard let pair = events[value.eventID] else { throw Failure.missingDependency }
            return pair.target
        }

        func index() throws {
            for record in source.history.receipts {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
                allSourceIDs.insert(envelope.mutationID)
                guard envelope.workspaceID == source.workspaceID else { continue }
                guard revisions.updateValue(receipt.resultingRevision.workspaceRevision,
                                            forKey: envelope.mutationID) == nil else { throw Failure.invalidSource }
                switch envelope.command {
                case let .applySurveyDefinition(value):
                    _ = try SurveyDefinitionMutationReceiptV1(mutation: value, mutationReceipt: receipt)
                    try authenticateExternal(envelope, receipt)
                    if value.appendsRelease { definitionProducers.append(value) }
                case let .applyPackagePromotion(value):
                    _ = try PackagePromotionMutationReceiptV1(mutation: value, mutationReceipt: receipt)
                    try authenticateExternal(envelope, receipt)
                    packageProducers.append(value)
                default: break
                }
            }
            for entry in source.entries where entry.family == .schedule {
                guard case let .applySchedule(value) = entry.envelope.command else { throw Failure.invalidSource }
                let original = Original(entry: entry, mutation: value)
                guard nodes.updateValue(original, forKey: value.mutationID) == nil else { throw Failure.invalidSource }
                originals.append(original)
                try register(value.mutationID, identity.destinationScheduleMutationID(for: value.mutationID))
                switch value.payload {
                case let .appendRelease(value, _):
                    guard releaseOwners.updateValue(value, forKey: value.releaseID) == nil else { throw Failure.invalidSource }
                case let .appendExceptionCalendarRelease(value, _):
                    guard calendarOwners.updateValue(value, forKey: value.releaseID) == nil else { throw Failure.invalidSource }
                case let .appendOverrideEvent(value, _, _):
                    guard overrideOwners.updateValue(value, forKey: value.eventID) == nil else { throw Failure.invalidSource }
                    if value.kind == .addOne {
                        let id = try ScheduleOccurrenceLineageV1.addedOccurrenceID(
                            scheduleDefinitionID: value.scheduleRelease.scheduleDefinitionID,
                            identityNamespaceID: value.scheduleRelease.occurrenceIdentityNamespaceID, overrideEvent: value)
                        guard addedIdentities.updateValue(value, forKey: OccurrenceKey(value.scheduleRelease, id)) == nil else {
                            throw Failure.collision
                        }
                    }
                case let .appendOccurrenceEvent(value, _, _), let .startOccurrence(value, _, _):
                    try indexEvent(value)
                case let .generateOccurrences(_, _, values):
                    for value in values { try indexEvent(value) }
                }
            }
            guard Set(identities.keys).isDisjoint(with: Set(addedIdentities.keys)) else { throw Failure.collision }
            for command in work.commands { try register(command.source.envelope.mutationID, command.mutation.mutationID) }
            for command in round.commands { try register(command.source.envelope.mutationID, command.mutation.mutationID) }
        }

        func authenticateExternal(_ envelope: MutationEnvelopeV1, _ receipt: MutationReceiptV1) throws {
            guard receipt.envelopeSHA256 == (try envelope.canonicalSHA256()),
                  receipt.identity.workspaceID == envelope.workspaceID,
                  receipt.mutationID == envelope.mutationID,
                  receipt.commandBodySHA256 == envelope.commandBodySHA256,
                  receipt.expectedRevision == envelope.expectedRevision,
                  !source.history.quarantines.contains(where: {
                      $0.workspaceID == source.workspaceID && $0.mutationID == envelope.mutationID.rawValue
                  }) else { throw Failure.invalidSource }
        }

        func indexEvent(_ value: OccurrenceHistoryEventV1) throws {
            guard eventOwners.updateValue(value, forKey: value.eventID) == nil else { throw Failure.invalidSource }
            let key = OccurrenceKey(value.scheduleRelease, value.occurrenceID)
            if let prior = identities[key] {
                guard prior.nominalBasis.nominalKey == value.nominalBasis.nominalKey,
                      prior.identityPredecessorOccurrenceID == value.identityPredecessorOccurrenceID,
                      prior.identityCompletionEventSHA256 == value.identityCompletionEventSHA256 else { throw Failure.invalidSource }
            } else { identities[key] = value }
        }

        func validateBindings() throws {
            var definitionKeys = Set<SurveyDefinitionReleaseReferenceV1>()
            for binding in definitions {
                let original = binding.source
                try original.validate(); try binding.target.validate()
                guard original.workspaceID == source.workspaceID,
                      definitionKeys.insert(try .init(original)).inserted else { throw Failure.invalidSource }
                let producers = definitionProducers.filter { $0.release == original }
                guard producers.count <= 1, (producers.isEmpty) == (binding.producer == nil) else { throw Failure.missingDependency }
                if let pair = binding.producer {
                    try pair.source.validate(); try pair.target.validate()
                    guard producers == [pair.source], pair.source.appendsRelease, pair.target.appendsRelease,
                          pair.source.release == original, pair.target.release == binding.target,
                          pair.target.workspaceID == workspace else { throw Failure.invalidSource }
                    try register(pair.source.mutationID, pair.target.mutationID)
                }
                let expected = try SurveyDefinitionReleaseV1(
                    releaseID: original.releaseID, workspaceID: workspace, definitionID: original.definitionID,
                    activityKind: original.activityKind, ownerPackageID: original.ownerPackageID,
                    sections: original.sections, completionRules: original.completionRules,
                    claimsProfile: original.claimsProfile, reportProjection: original.reportProjection,
                    localizationReleaseSHA256: original.localizationReleaseSHA256,
                    supersedesReleaseID: original.supersedesReleaseID, revision: original.revision,
                    mutationID: binding.producer?.target.mutationID ?? original.mutationID,
                    authoredBy: actor(original.authoredBy), authoredAt: original.authoredAt)
                guard expected == binding.target else { throw Failure.invalidSource }
            }
            var packageKeys = Set<String>()
            for binding in packages {
                try binding.source.validate(); try binding.target.validate()
                guard binding.source.state == .published, binding.target == binding.source,
                      packageKeys.insert(binding.source.packageReleaseID).inserted else { throw Failure.invalidSource }
                let producers = packageProducers.filter { $0.promotedRelease.packageRelease == binding.source }
                guard producers.count == binding.producers.count,
                      Set(binding.producers.map { $0.source.mutationID }).count == producers.count,
                      Set(binding.producers.map { $0.target.mutationID }).count == producers.count else { throw Failure.missingDependency }
                for pair in binding.producers {
                    try pair.source.validate(); try pair.target.validate()
                    guard producers.contains(pair.source), pair.target.workspaceID == workspace,
                          pair.source.promotedRelease.packageRelease == binding.source,
                          pair.target.promotedRelease.packageRelease == binding.target else { throw Failure.invalidSource }
                    try register(pair.source.mutationID, pair.target.mutationID)
                }
            }
        }

        func workDefinition(_ reference: ScheduledWorkDefinitionReferenceV1) throws -> ScheduledWorkDefinitionReferenceV1 {
            guard reference.definitionWorkspaceID == source.workspaceID else { throw Failure.invalidSource }
            let matchingDefinitions = try definitions.filter { try SurveyDefinitionReleaseReferenceV1($0.source) == reference.definitionRelease }
            let matchingPackages = packages.filter {
                let value = $0.source
                return value.packageReleaseID == reference.packageReleaseID && value.packageID == reference.packageID
                    && value.packageContentVersion == reference.packageContentVersion
                    && value.packageSHA256 == reference.packageSHA256 && value.workflowSHA256 == reference.workflowSHA256
            }
            guard matchingDefinitions.count == 1, matchingPackages.count == 1,
                  let current = stack.last, let consumerRevision = revisions[current] else { throw Failure.missingDependency }
            let definition = matchingDefinitions[0], package = matchingPackages[0]
            guard try ScheduledWorkDefinitionReferenceV1(kind: reference.kind, definition: definition.source,
                                                        packageRelease: package.source) == reference else { throw Failure.invalidSource }
            consumedDefinitions.insert(reference.definitionRelease)
            consumedPackages.insert(reference.packageReleaseID)
            if let pair = definition.producer { try depend(pair.source.mutationID, pair.target.mutationID) }
            for pair in package.producers {
                guard let revision = revisions[pair.source.mutationID] else { throw Failure.missingDependency }
                if revision < consumerRevision { try depend(pair.source.mutationID, pair.target.mutationID) }
            }
            return try .init(kind: reference.kind, definition: definition.target, packageRelease: package.target)
        }

        func build(_ id: MutationIDV1) throws -> Command {
            if let result = commands[id] { return result }
            guard !stack.contains(id), let original = nodes[id], let targetID = mappedIDs[id] else {
                throw Failure.missingDependency
            }
            stack.append(id)
            defer { stack.removeLast() }
            let payload: ScheduleMutationPayloadV1
            switch original.mutation.payload {
            case let .appendRelease(value, prior):
                let predecessor = try prior.map { try release($0) }
                let target = try makeRelease(value, predecessor: predecessor, mutationID: targetID)
                releases[value.releaseID] = Pair(source: value, target: target)
                payload = .appendRelease(target, predecessor: predecessor)
            case let .appendExceptionCalendarRelease(value, prior):
                let predecessor = try prior.map { try calendar($0) }
                let target = try ExceptionCalendarReleaseV1(
                    workspaceID: workspace, calendarID: value.calendarID, releaseID: value.releaseID,
                    name: value.name, ianaTimeZoneIdentifier: value.ianaTimeZoneIdentifier,
                    effectiveRange: value.effectiveRange, baseIncludedWeekdays: value.baseIncludedWeekdays,
                    excludedDates: value.excludedDates, excludedRanges: value.excludedRanges,
                    includedOverrideDates: value.includedOverrideDates,
                    supersedesReleaseID: predecessor?.releaseID, predecessorReleaseSHA256: predecessor?.releaseSHA256,
                    revision: value.revision, mutationID: targetID,
                    authoredBy: actor(value.authoredBy), authoredAt: value.authoredAt)
                calendars[value.releaseID] = Pair(source: value, target: target)
                payload = .appendExceptionCalendarRelease(target, predecessor: predecessor)
            case let .appendOverrideEvent(value, prior, sourceRelease):
                let targetRelease = try release(sourceRelease)
                let predecessor = try prior.map { try mappedOverride($0) }
                let reference = try ScheduleDefinitionReleaseReferenceV1(targetRelease)
                let frontier = try overrideFrontier(value, release: sourceRelease)
                let targetScope: ScheduleOverrideTargetV1
                switch value.target {
                case let .occurrence(id, nominalDate):
                    targetScope = .occurrence(try occurrence(id, reference: value.scheduleRelease), nominalDate: nominalDate)
                case let .nominalDate(date): targetScope = .nominalDate(date)
                }
                let target = try ScheduleOverrideEventV1(
                    eventID: value.eventID, workspaceID: workspace, scheduleRelease: reference,
                    target: targetScope, scope: value.scope, kind: value.kind, effectiveRange: value.effectiveRange,
                    replacementDate: value.replacementDate, replacementWindow: value.replacementWindow,
                    reasonCode: value.reasonCode, expectedScheduleRevision: value.expectedScheduleRevision,
                    expectedOverrideFrontierSHA256: frontier, supersedesEventID: predecessor?.eventID,
                    predecessorEventSHA256: predecessor?.eventSHA256, revision: value.revision, mutationID: targetID,
                    recordedBy: actor(value.recordedBy), recordedAt: value.recordedAt)
                overrides[value.eventID] = Pair(source: value, target: target)
                payload = .appendOverrideEvent(target, predecessor: predecessor, release: targetRelease)
            case let .appendOccurrenceEvent(value, prior, sourceRelease):
                let targetRelease = try release(sourceRelease)
                let predecessor = try prior.map { try event($0) }
                let target = try makeEvent(value, predecessor: predecessor, release: targetRelease, mutationID: targetID)
                events[value.eventID] = Pair(source: value, target: target)
                payload = .appendOccurrenceEvent(target, predecessor: predecessor, release: targetRelease)
            case let .startOccurrence(value, prior, sourceRelease):
                let targetRelease = try release(sourceRelease)
                let predecessor = try event(prior)
                let target = try makeEvent(value, predecessor: predecessor, release: targetRelease, mutationID: targetID)
                events[value.eventID] = Pair(source: value, target: target)
                payload = .startOccurrence(target, predecessor: predecessor, release: targetRelease)
            case let .generateOccurrences(sourceRelease, plan, sourceEvents):
                let targetRelease = try release(sourceRelease)
                let targetEvents = try sourceEvents.map {
                    try makeEvent($0, predecessor: nil, release: targetRelease, mutationID: targetID)
                }
                // Original typed validation establishes the exact candidate/event
                // bijection. Rebuild that same atomic set from its mapped events.
                let candidates = targetEvents.map {
                    OccurrenceGenerationCandidateV1(occurrenceID: $0.occurrenceID,
                        nominalBasis: $0.nominalBasis, effectiveBasis: $0.effectiveBasis,
                        predecessorOccurrenceID: $0.identityPredecessorOccurrenceID,
                        completionEventSHA256: $0.identityCompletionEventSHA256)
                }
                let existing = try plan.existingOccurrenceIDs.map { try occurrence($0, reference: plan.scheduleRelease) }
                let targetPlan = try OccurrenceGenerationPlanV1(definition: targetRelease, window: plan.window,
                                                               candidates: candidates, existingOccurrenceIDs: existing)
                for (original, target) in zip(sourceEvents, targetEvents) {
                    events[original.eventID] = Pair(source: original, target: target)
                }
                payload = .generateOccurrences(release: targetRelease, plan: targetPlan, events: targetEvents)
            }
            let mutation = try ScheduleMutationV1(workspaceID: workspace, mutationID: targetID, payload: payload)
            let result = try Command(sourceEntry: original.entry, mutation: mutation, dependencies: dependencies[id] ?? [:])
            commands[id] = result
            return result
        }

        func makeRelease(_ value: ScheduleDefinitionReleaseV1, predecessor: ScheduleDefinitionReleaseV1?,
                         mutationID: MutationIDV1) throws -> ScheduleDefinitionReleaseV1 {
            var recurrence = value.recurrence
            var timeBasis = value.timeBasis
            if case let .advanced(configuration) = recurrence {
                let targetCalendar = try calendar(configuration.calendarRelease)
                recurrence = .advanced(.init(recurrence: configuration.recurrence,
                                              calendarRelease: targetCalendar.reference,
                                              businessDayAdjustmentPolicy: configuration.businessDayAdjustmentPolicy))
                let old = value.timeBasis
                timeBasis = try .init(calendar: old.calendar, ianaTimeZoneIdentifier: old.ianaTimeZoneIdentifier,
                    timeZoneRuleSetVersion: old.timeZoneRuleSetVersion, timeZoneRuleSetSHA256: old.timeZoneRuleSetSHA256,
                    ambiguousTimePolicy: old.ambiguousTimePolicy, nonexistentTimePolicy: old.nonexistentTimePolicy,
                    calendarBasisID: old.calendarBasisID, calendarBasisRevision: old.calendarBasisRevision,
                    calendarBasisSHA256: targetCalendar.releaseSHA256)
            }
            return try .init(scheduleDefinitionID: value.scheduleDefinitionID, releaseID: value.releaseID,
                workspaceID: workspace, occurrenceIdentityNamespaceID: value.occurrenceIdentityNamespaceID,
                action: value.action, lifecycleState: value.lifecycleState, recurrence: recurrence, timeBasis: timeBasis,
                startsAtUTC: value.startsAtUTC, endsAtUTC: value.endsAtUTC,
                generationHorizonDays: value.generationHorizonDays, maximumGeneratedOccurrences: value.maximumGeneratedOccurrences,
                readyLeadSeconds: value.readyLeadSeconds, overdueGraceSeconds: value.overdueGraceSeconds,
                subject: value.subject, workDefinition: workDefinition(value.workDefinition),
                assignee: value.assignee.map { try actor($0) }, supersedesReleaseID: predecessor?.releaseID,
                predecessorReleaseSHA256: predecessor?.releaseSHA256, revision: value.revision, mutationID: mutationID,
                authoredBy: actor(value.authoredBy), authoredAt: value.authoredAt)
        }

        func overrideFrontier(_ value: ScheduleOverrideEventV1, release: ScheduleDefinitionReleaseV1) throws -> String {
            var admitted = Set<ScheduleDefinitionReleaseReferenceV1>()
            var cursor: ScheduleDefinitionReleaseV1? = release
            var seen = Set<UUID>()
            while let current = cursor {
                guard current.workspaceID == release.workspaceID,
                      current.scheduleDefinitionID == release.scheduleDefinitionID,
                      current.occurrenceIdentityNamespaceID == release.occurrenceIdentityNamespaceID else { break }
                guard seen.insert(current.releaseID).inserted,
                      releaseOwners[current.releaseID] == current else { throw Failure.invalidSource }
                admitted.insert(try .init(current))
                if let predecessorID = current.supersedesReleaseID {
                    guard let predecessor = releaseOwners[predecessorID],
                          predecessor.releaseSHA256 == current.predecessorReleaseSHA256 else { throw Failure.missingDependency }
                    cursor = predecessor
                } else { cursor = nil }
            }
            guard let revision = revisions[value.mutationID] else { throw Failure.missingDependency }
            let prior = try overrideOwners.values.filter {
                guard let priorRevision = revisions[$0.mutationID] else { throw Failure.missingDependency }
                return priorRevision < revision && admitted.contains($0.scheduleRelease)
            }.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
            try ScheduleOverridePrecedenceV1.validateExpectedFrontier(value, against: prior)
            return try ScheduleOverridePrecedenceV1.closureSHA256(prior.map { try mappedOverride($0) })
        }

        func occurrence(_ id: OccurrenceIDV1, reference: ScheduleDefinitionReleaseReferenceV1) throws -> OccurrenceIDV1 {
            let key = OccurrenceKey(reference, id)
            guard visitingIdentities.insert(key).inserted else { throw Failure.invalidSource }
            defer { visitingIdentities.remove(key) }
            let target: OccurrenceIDV1
            if let value = identities[key] {
                let ancestry = try ancestry(value)
                target = try .init(scheduleDefinitionID: key.schedule, identityNamespaceID: key.namespace,
                                   nominalKey: value.nominalBasis.nominalKey,
                                   predecessorOccurrenceID: ancestry.0, completionEventSHA256: ancestry.1)
            } else if let added = addedIdentities[key] {
                target = try ScheduleOccurrenceLineageV1.addedOccurrenceID(scheduleDefinitionID: key.schedule,
                    identityNamespaceID: key.namespace, overrideEvent: mappedOverride(added))
            } else {
                // A forward override target has no required event-row preimage.
                target = id
            }
            guard mappedIdentities[key].map({ $0 == target }) ?? true,
                  !mappedIdentities.contains(where: {
                      $0.key != key && $0.key.schedule == key.schedule && $0.key.namespace == key.namespace && $0.value == target
                  }) else { throw Failure.collision }
            mappedIdentities[key] = target
            return target
        }

        func replacementOccurrence(_ id: OccurrenceIDV1) throws -> OccurrenceIDV1 {
            // Rule rotation can reference a different namespace. Use the exact
            // known preimage there before preserving an opaque forward reference.
            let matches = identities.keys.filter { $0.occurrence == id }
                + addedIdentities.keys.filter { $0.occurrence == id }
            guard matches.count <= 1 else { throw Failure.missingDependency }
            guard let key = matches.first else { return id }
            if let event = identities[key] { return try occurrence(id, reference: event.scheduleRelease) }
            if let event = addedIdentities[key] { return try occurrence(id, reference: event.scheduleRelease) }
            throw Failure.missingDependency
        }

        func ancestry(_ value: OccurrenceHistoryEventV1) throws -> (OccurrenceIDV1?, String?) {
            guard let predecessorID = value.identityPredecessorOccurrenceID,
                  let digest = value.identityCompletionEventSHA256 else {
                guard value.identityPredecessorOccurrenceID == nil, value.identityCompletionEventSHA256 == nil else {
                    throw Failure.invalidSource
                }
                return (nil, nil)
            }
            let matches = eventOwners.values.filter {
                $0.eventSHA256 == digest && $0.occurrenceID == predecessorID
                    && $0.scheduleRelease.workspaceID == value.scheduleRelease.workspaceID
                    && $0.scheduleRelease.scheduleDefinitionID == value.scheduleRelease.scheduleDefinitionID
                    && $0.scheduleRelease.occurrenceIdentityNamespaceID == value.scheduleRelease.occurrenceIdentityNamespaceID
            }
            guard matches.count == 1 else { throw Failure.missingDependency }
            let sourceAnchor = matches[0]
            if sourceAnchor.action != .complete {
                guard sourceAnchor.exception?.kind == .skipped,
                      let release = releaseOwners[value.scheduleRelease.releaseID],
                      case let .advanced(configuration) = release.recurrence,
                      case let .completionRelative(_, _, gapPolicy) = configuration.recurrence,
                      gapPolicy == .anchorToNominalAfterExplicitSkip else { throw Failure.invalidSource }
            }
            let targetAnchor = try event(sourceAnchor)
            let targetID = try occurrence(predecessorID, reference: sourceAnchor.scheduleRelease)
            guard targetAnchor.occurrenceID == targetID else { throw Failure.invalidSource }
            return (targetID, targetAnchor.eventSHA256)
        }

        func basis(_ value: ResolvedOccurrenceBasisV1, timeBasisSHA256: String) throws -> ResolvedOccurrenceBasisV1 {
            let provenance: String?
            if let digest = value.adjustmentProvenanceSHA256 {
                let overrides = overrideOwners.values.filter { $0.eventSHA256 == digest }
                let calendars = calendarOwners.values.filter { $0.releaseSHA256 == digest }
                guard overrides.count + calendars.count == 1 else { throw Failure.missingDependency }
                if let source = overrides.first { provenance = try mappedOverride(source).eventSHA256 }
                else if let source = calendars.first { provenance = try calendar(source).releaseSHA256 }
                else { throw Failure.missingDependency }
            } else { provenance = nil }
            let target = ResolvedOccurrenceBasisV1(nominalLocalDate: value.nominalLocalDate,
                nominalLocalTime: value.nominalLocalTime, resolvedAtUTC: value.resolvedAtUTC,
                utcOffsetSeconds: value.utcOffsetSeconds, disposition: value.disposition,
                timeBasisSHA256: timeBasisSHA256, adjustmentProvenanceSHA256: provenance)
            try target.validate()
            return target
        }

        func workInstance(_ value: ScheduledWorkInstanceReferenceV1) throws -> ScheduledWorkInstanceReferenceV1 {
            switch value {
            case let .workPacket(reference):
                let target = try work.targetManifest(for: reference)
                let matches = try work.manifests.filter { try WorkPacketManifestReferenceV1($0.source) == reference }
                guard matches.count == 1 else { throw Failure.missingDependency }
                try depend(matches[0].sourceMutationID, matches[0].targetMutationID)
                return try .workPacket(WorkPacketManifestReferenceV1(target))
            case let .roundSession(id, revision, digest):
                let reference = try RoundSessionReferenceV1(workspaceID: source.workspaceID,
                                                            sessionID: id, revision: revision, sessionSHA256: digest)
                let target = try round.targetSession(for: reference)
                let matches = try round.commands.filter {
                    guard case let .applyRoundSession(original) = $0.source.envelope.command else { throw Failure.invalidSource }
                    return try original.session.reference == reference
                }
                guard matches.count == 1 else { throw Failure.missingDependency }
                try depend(matches[0].source.envelope.mutationID, matches[0].mutation.mutationID)
                return .roundSession(sessionID: target.sessionID, revision: target.revision, sessionSHA256: target.sessionSHA256)
            }
        }

        func makeEvent(_ value: OccurrenceHistoryEventV1, predecessor: OccurrenceHistoryEventV1?,
                       release: ScheduleDefinitionReleaseV1, mutationID: MutationIDV1) throws -> OccurrenceHistoryEventV1 {
            let reference = try ScheduleDefinitionReleaseReferenceV1(release)
            let id = try occurrence(value.occurrenceID, reference: value.scheduleRelease)
            let identityBasis = try ancestry(value)
            let nominal = try basis(value.nominalBasis, timeBasisSHA256: reference.timeBasisSHA256)
            let effective = try basis(value.effectiveBasis, timeBasisSHA256: reference.timeBasisSHA256)
            let exception: ScheduleExceptionV1?
            if let original = value.exception {
                guard let predecessor else { throw Failure.missingDependency }
                exception = try .init(exceptionID: original.exceptionID, kind: original.kind,
                    priorEffectiveBasisSHA256: ScheduleCanonicalCodecV1.sha256(predecessor.effectiveBasis),
                    replacementBasis: original.replacementBasis.map { try basis($0, timeBasisSHA256: reference.timeBasisSHA256) },
                    replacementOccurrenceID: original.replacementOccurrenceID.map { try replacementOccurrence($0) },
                    reasonCode: original.reasonCode, recordedBy: actor(original.recordedBy), recordedAt: original.recordedAt)
            } else { exception = nil }
            return try .init(eventID: value.eventID, workspaceID: workspace, occurrenceID: id,
                identityPredecessorOccurrenceID: identityBasis.0, identityCompletionEventSHA256: identityBasis.1,
                scheduleRelease: reference, action: value.action, nominalBasis: nominal, effectiveBasis: effective,
                exception: exception, workInstance: value.workInstance.map { try workInstance($0) },
                completedAt: value.completedAt, predecessor: predecessor, revision: value.revision, mutationID: mutationID,
                recordedBy: actor(value.recordedBy), recordedAt: value.recordedAt)
        }

        func actor(_ value: ActorSnapshotV1) throws -> ActorSnapshotV1 {
            guard value.workspaceID == source.workspaceID else { throw Failure.invalidSource }
            return try .init(snapshotID: value.snapshotID, workspaceID: workspace,
                             actor: LocalActorReferenceV1(actorReferenceID: value.actor.actorReferenceID,
                                 workspaceID: workspace, partyID: value.actor.partyID, displayName: value.actor.displayName),
                             responsibility: value.responsibility, displayNameAtTime: value.displayNameAtTime,
                             capturedAt: value.capturedAt)
        }
    }
}
