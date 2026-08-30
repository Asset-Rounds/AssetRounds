import Foundation

enum ScheduleOverrideScopeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case thisOccurrence = "THIS_OCCURRENCE"
    case thisAndFuture = "THIS_AND_FUTURE"
    case entireSeries = "ENTIRE_SERIES"
}

enum ScheduleOccurrenceOverrideKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case skip = "SKIP", move = "MOVE", addOne = "ADD_ONE"
}

enum ScheduleOverrideTargetV1: Codable, Equatable, Hashable, Sendable {
    case occurrence(OccurrenceIDV1, nominalDate: ScheduleLocalDateV1)
    case nominalDate(ScheduleLocalDateV1)

    var nominalDate: ScheduleLocalDateV1 {
        switch self { case .occurrence(_, let date), .nominalDate(let date): return date }
    }
    var occurrenceID: OccurrenceIDV1? {
        if case .occurrence(let value, _) = self { return value }; return nil
    }
    func validate() throws { try nominalDate.validate(); try occurrenceID?.validate() }
}

struct ScheduleOverrideEventReferenceV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let scheduleDefinitionID: UUID
    let eventID: UUID
    let revision: UInt64
    let eventSHA256: String
    func validate() throws {
        try ScheduleLimitsV1.id(scheduleDefinitionID); try ScheduleLimitsV1.id(eventID)
        try ScheduleLimitsV1.revision(revision); try ScheduleLimitsV1.digest(eventSHA256)
    }
}

struct ScheduleOverrideEventV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let eventID: UUID
    let workspaceID: WorkspaceID
    let scheduleRelease: ScheduleDefinitionReleaseReferenceV1
    let target: ScheduleOverrideTargetV1
    let scope: ScheduleOverrideScopeV1
    let kind: ScheduleOccurrenceOverrideKindV1
    let effectiveRange: ScheduleLocalDateRangeV1
    let replacementDate: ScheduleLocalDateV1?
    let replacementWindow: ScheduleLocalAnchorV1?
    let reasonCode: String
    let expectedScheduleRevision: UInt64
    let expectedOverrideFrontierSHA256: String
    let supersedesEventID: UUID?
    let predecessorEventSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let eventSHA256: String

    init(eventID: UUID, workspaceID: WorkspaceID,
         scheduleRelease: ScheduleDefinitionReleaseReferenceV1,
         target: ScheduleOverrideTargetV1, scope: ScheduleOverrideScopeV1,
         kind: ScheduleOccurrenceOverrideKindV1,
         effectiveRange: ScheduleLocalDateRangeV1,
         replacementDate: ScheduleLocalDateV1? = nil,
         replacementWindow: ScheduleLocalAnchorV1? = nil,
         reasonCode: String, expectedScheduleRevision: UInt64,
         expectedOverrideFrontierSHA256: String,
         supersedesEventID: UUID? = nil, predecessorEventSHA256: String? = nil,
         revision: UInt64, mutationID: MutationIDV1,
         recordedBy: ActorSnapshotV1, recordedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.eventID = eventID; self.workspaceID = workspaceID
        self.scheduleRelease = scheduleRelease; self.target = target; self.scope = scope; self.kind = kind
        self.effectiveRange = effectiveRange; self.replacementDate = replacementDate
        self.replacementWindow = replacementWindow; self.reasonCode = reasonCode
        self.expectedScheduleRevision = expectedScheduleRevision; self.supersedesEventID = supersedesEventID
        self.expectedOverrideFrontierSHA256 = expectedOverrideFrontierSHA256
        self.predecessorEventSHA256 = predecessorEventSHA256; self.revision = revision
        self.mutationID = mutationID; self.recordedBy = recordedBy; self.recordedAt = recordedAt
        eventSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            eventID: eventID, workspaceID: workspaceID, scheduleRelease: scheduleRelease,
            target: target, scope: scope, kind: kind, effectiveRange: effectiveRange,
            replacementDate: replacementDate, replacementWindow: replacementWindow,
            reasonCode: reasonCode, expectedScheduleRevision: expectedScheduleRevision,
            expectedOverrideFrontierSHA256: expectedOverrideFrontierSHA256,
            supersedesEventID: supersedesEventID, predecessorEventSHA256: predecessorEventSHA256,
            revision: revision, mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt))
        try validate()
    }

    var reference: ScheduleOverrideEventReferenceV1 { .init(workspaceID: workspaceID,
        scheduleDefinitionID: scheduleRelease.scheduleDefinitionID, eventID: eventID,
        revision: revision, eventSHA256: eventSHA256) }

    func validate() throws {
        try ScheduleLimitsV1.id(eventID); try scheduleRelease.validate(); try target.validate()
        try effectiveRange.validate(); try replacementDate?.validate(); try replacementWindow?.validate()
        try ScheduleLimitsV1.token(reasonCode); try ScheduleLimitsV1.revision(expectedScheduleRevision)
        try ScheduleLimitsV1.digest(expectedOverrideFrontierSHA256)
        try ScheduleLimitsV1.revision(revision); try recordedBy.validate(); try ScheduleLimitsV1.instant(recordedAt)
        let replacementIsExact = kind == .skip
            ? replacementDate == nil && replacementWindow == nil
            : replacementDate != nil && replacementWindow != nil
        let exactTargetRequired = scope == .thisOccurrence && kind != .addOne
        let addIsOne = kind != .addOne || scope == .thisOccurrence
        guard schemaVersion == Self.schemaVersion, workspaceID == scheduleRelease.workspaceID,
              recordedBy.workspaceID == workspaceID, recordedBy.responsibility == .recordedBy,
              expectedScheduleRevision == scheduleRelease.revision,
              effectiveRange.contains(target.nominalDate), replacementIsExact, addIsOne,
              (!exactTargetRequired || target.occurrenceID != nil),
              revision > 0,
              (revision == 1) == (supersedesEventID == nil && predecessorEventSHA256 == nil),
              supersedesEventID != eventID,
              predecessorEventSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              eventSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else {
            throw ScheduleFailureV1.invalidValue
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validate(); try validate()
        guard predecessor.workspaceID == workspaceID,
              predecessor.scheduleRelease.scheduleDefinitionID == scheduleRelease.scheduleDefinitionID,
              revision == predecessor.revision + 1, revision > predecessor.revision,
              supersedesEventID == predecessor.eventID,
              predecessorEventSHA256 == predecessor.eventSHA256,
              eventID != predecessor.eventID, mutationID != predecessor.mutationID else {
            throw ScheduleFailureV1.invalidSuccessor
        }
    }

    func applies(to occurrenceID: OccurrenceIDV1, nominalDate: ScheduleLocalDateV1) -> Bool {
        guard effectiveRange.contains(nominalDate) else { return false }
        switch scope {
        case .thisOccurrence: return target.occurrenceID == occurrenceID
        case .thisAndFuture: return nominalDate >= target.nominalDate
        case .entireSeries: return true
        }
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, eventID: eventID, workspaceID: workspaceID,
        scheduleRelease: scheduleRelease, target: target, scope: scope, kind: kind,
        effectiveRange: effectiveRange, replacementDate: replacementDate,
        replacementWindow: replacementWindow, reasonCode: reasonCode,
        expectedScheduleRevision: expectedScheduleRevision,
        expectedOverrideFrontierSHA256: expectedOverrideFrontierSHA256,
        supersedesEventID: supersedesEventID,
        predecessorEventSHA256: predecessorEventSHA256, revision: revision,
        mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let eventID: UUID; let workspaceID: WorkspaceID
        let scheduleRelease: ScheduleDefinitionReleaseReferenceV1; let target: ScheduleOverrideTargetV1
        let scope: ScheduleOverrideScopeV1; let kind: ScheduleOccurrenceOverrideKindV1
        let effectiveRange: ScheduleLocalDateRangeV1; let replacementDate: ScheduleLocalDateV1?
        let replacementWindow: ScheduleLocalAnchorV1?; let reasonCode: String
        let expectedScheduleRevision: UInt64; let expectedOverrideFrontierSHA256: String
        let supersedesEventID: UUID?
        let predecessorEventSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1
        let recordedBy: ActorSnapshotV1; let recordedAt: Date }
}

enum ScheduleOverridePrecedenceLevelV1: Int, Codable, Comparable, Hashable, Sendable {
    case baseRecurrence = 0, exceptionCalendar = 1, effectiveSeriesOverride = 2, explicitOccurrenceOverride = 3
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ScheduleOverrideResolutionV1: Codable, Equatable, Sendable {
    let level: ScheduleOverridePrecedenceLevelV1
    let event: ScheduleOverrideEventV1?
    let effectiveDate: ScheduleLocalDateV1?
    let effectiveWindow: ScheduleLocalAnchorV1?
    let adjustmentReason: ScheduleBasisAdjustmentReasonV1
    let requiresManualResolution: Bool
}

enum ScheduleOverridePrecedenceV1 {
    static func validateClosure(_ events: [ScheduleOverrideEventV1],
                                for scheduleRelease: ScheduleDefinitionReleaseReferenceV1) throws {
        try scheduleRelease.validate()
        _ = try activeEvents(events)
        guard events.allSatisfy({ event in
            event.workspaceID == scheduleRelease.workspaceID
                && event.scheduleRelease.workspaceID == scheduleRelease.workspaceID
                && event.scheduleRelease.scheduleDefinitionID == scheduleRelease.scheduleDefinitionID
                && event.scheduleRelease.occurrenceIdentityNamespaceID
                    == scheduleRelease.occurrenceIdentityNamespaceID
        }) else { throw ScheduleFailureV1.staleBasis }
    }

    static func closureSHA256(_ events: [ScheduleOverrideEventV1]) throws -> String {
        let ordered = try activeEvents(events).sorted {
            $0.eventID.uuidString.lowercased() < $1.eventID.uuidString.lowercased()
        }
        return try ScheduleCanonicalCodecV1.sha256(OverrideClosure(events: ordered))
    }

    static func validateExpectedFrontier(_ event: ScheduleOverrideEventV1,
                                         against existingEvents: [ScheduleOverrideEventV1]) throws {
        try event.validate()
        guard event.expectedOverrideFrontierSHA256 == (try closureSHA256(existingEvents)) else {
            throw ScheduleFailureV1.staleBasis
        }
    }

    static func activeEvents(_ events: [ScheduleOverrideEventV1]) throws -> [ScheduleOverrideEventV1] {
        try events.forEach { try $0.validate() }
        guard Set(events.map(\.eventID)).count == events.count else { throw ScheduleFailureV1.divergentReplay }
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.eventID, $0) })
        for event in events where event.revision > 1 {
            guard let predecessorID = event.supersedesEventID, let predecessor = byID[predecessorID] else {
                throw ScheduleFailureV1.staleBasis
            }
            try event.validateSuccessor(of: predecessor)
        }
        let superseded = Set(events.compactMap(\.supersedesEventID))
        return events.filter { !superseded.contains($0.eventID) }.sorted {
            if $0.target.nominalDate != $1.target.nominalDate { return $0.target.nominalDate < $1.target.nominalDate }
            return $0.eventID.uuidString.lowercased() < $1.eventID.uuidString.lowercased()
        }
    }

    static func resolve(occurrenceID: OccurrenceIDV1, nominalDate: ScheduleLocalDateV1,
                        nominalWindow: ScheduleLocalAnchorV1,
                        scheduleRelease: ScheduleDefinitionReleaseReferenceV1,
                        calendar: ExceptionCalendarReleaseV1,
                        adjustmentPolicy: BusinessDayAdjustmentPolicyV1,
                        events: [ScheduleOverrideEventV1]) throws -> ScheduleOverrideResolutionV1 {
        try occurrenceID.validate(); try nominalDate.validate(); try nominalWindow.validate(); try calendar.validate()
        try validateClosure(events, for: scheduleRelease)
        guard calendar.workspaceID == scheduleRelease.workspaceID else { throw ScheduleFailureV1.wrongWorkspace }
        let applicable = try activeEvents(events).filter { $0.applies(to: occurrenceID, nominalDate: nominalDate) }
        let exact = applicable.filter { $0.scope == .thisOccurrence }
        let series = applicable.filter { $0.scope != .thisOccurrence }
        guard exact.count <= 1, series.count <= 1 else { throw ScheduleFailureV1.divergentReplay }
        if let event = exact.first ?? series.first {
            switch event.kind {
            case .skip:
                return .init(level: event.scope == .thisOccurrence ? .explicitOccurrenceOverride : .effectiveSeriesOverride,
                             event: event, effectiveDate: nil, effectiveWindow: nil,
                             adjustmentReason: .explicitSkip, requiresManualResolution: false)
            case .move, .addOne:
                return .init(level: event.scope == .thisOccurrence ? .explicitOccurrenceOverride : .effectiveSeriesOverride,
                             event: event, effectiveDate: event.replacementDate ?? nominalDate,
                             effectiveWindow: event.replacementWindow ?? nominalWindow,
                             adjustmentReason: event.kind == .move ? .explicitMove : .none,
                             requiresManualResolution: false)
            }
        }
        if try calendar.isIncluded(nominalDate) {
            let disposition = try calendar.disposition(on: nominalDate)
            return .init(level: .exceptionCalendar, event: nil, effectiveDate: nominalDate,
                         effectiveWindow: nominalWindow,
                         adjustmentReason: disposition == .includedOverride ? .includedOverride : .none,
                         requiresManualResolution: false)
        }
        switch adjustmentPolicy {
        case .skipWithReason:
            return .init(level: .exceptionCalendar, event: nil, effectiveDate: nil, effectiveWindow: nil,
                         adjustmentReason: .explicitSkip, requiresManualResolution: false)
        case .requireManualResolution:
            return .init(level: .exceptionCalendar, event: nil, effectiveDate: nil, effectiveWindow: nil,
                         adjustmentReason: .manualResolution, requiresManualResolution: true)
        case .nextIncludedDay, .previousIncludedDay:
            let step = adjustmentPolicy == .nextIncludedDay ? 1 : -1
            var candidate = nominalDate
            for _ in 0..<367 {
                candidate = try addingDays(step, to: candidate)
                if calendar.effectiveRange.contains(candidate), try calendar.isIncluded(candidate) {
                    return .init(level: .exceptionCalendar, event: nil, effectiveDate: candidate,
                                 effectiveWindow: nominalWindow,
                                 adjustmentReason: step > 0 ? .nextIncludedDay : .previousIncludedDay,
                                 requiresManualResolution: false)
                }
            }
            throw ScheduleFailureV1.limitExceeded
        }
    }

    private static func addingDays(_ value: Int, to date: ScheduleLocalDateV1) throws -> ScheduleLocalDateV1 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        guard let utc = TimeZone(secondsFromGMT: 0) else { throw ScheduleFailureV1.invalidValue }
        calendar.timeZone = utc
        guard let source = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)),
              let result = calendar.date(byAdding: .day, value: value, to: source) else {
            throw ScheduleFailureV1.invalidValue
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: result)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            throw ScheduleFailureV1.invalidValue
        }
        return try .init(year: year, month: month, day: day)
    }

    private struct OverrideClosure: Codable { let events: [ScheduleOverrideEventV1] }
}

enum ScheduleChangeDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case unchanged = "UNCHANGED", moved = "MOVED", skipped = "SKIPPED", cancelled = "CANCELLED"
    case created = "CREATED", requiresManualResolution = "REQUIRES_MANUAL_RESOLUTION"
}

struct ScheduleChangeOccurrenceInputV1: Codable, Equatable, Sendable {
    let occurrenceID: OccurrenceIDV1
    let state: OccurrenceStateV1
    let basis: OccurrenceScheduleBasisV2
    func validate() throws { try occurrenceID.validate(); try basis.validate() }
    var isImmutableHistory: Bool { state == .started || state == .completed || state == .missed }
}

struct ScheduleChangeEffectV1: Codable, Equatable, Sendable {
    let occurrenceID: OccurrenceIDV1
    let successorOccurrenceID: OccurrenceIDV1?
    let disposition: ScheduleChangeDispositionV1
    let priorBasisSHA256: String?
    let resultingBasis: OccurrenceScheduleBasisV2?
    let sourceOverrideEventSHA256: String?
}

struct ScheduleChangeFrontierV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let scheduleRelease: ScheduleDefinitionReleaseReferenceV1
    let calendarRelease: ExceptionCalendarReleaseReferenceV1
    let orderedOverrideEventSHA256s: [String]
    let occurrenceClosureSHA256: String
    let evaluatedRange: ScheduleLocalDateRangeV1
    let budget: AdvancedScheduleGenerationBudgetV1
    let frontierSHA256: String

    init(workspaceID: WorkspaceID, scheduleRelease: ScheduleDefinitionReleaseReferenceV1,
         calendarRelease: ExceptionCalendarReleaseReferenceV1,
         overrideEvents: [ScheduleOverrideEventV1], occurrenceClosureSHA256: String,
         evaluatedRange: ScheduleLocalDateRangeV1, budget: AdvancedScheduleGenerationBudgetV1) throws {
        try ScheduleOverridePrecedenceV1.validateClosure(overrideEvents, for: scheduleRelease)
        self.workspaceID = workspaceID; self.scheduleRelease = scheduleRelease; self.calendarRelease = calendarRelease
        orderedOverrideEventSHA256s = try ScheduleOverridePrecedenceV1.activeEvents(overrideEvents).map(\.eventSHA256).sorted()
        self.occurrenceClosureSHA256 = occurrenceClosureSHA256; self.evaluatedRange = evaluatedRange; self.budget = budget
        frontierSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID: workspaceID,
            scheduleRelease: scheduleRelease, calendarRelease: calendarRelease,
            orderedOverrideEventSHA256s: orderedOverrideEventSHA256s,
            occurrenceClosureSHA256: occurrenceClosureSHA256, evaluatedRange: evaluatedRange, budget: budget))
        try validate()
    }

    func validate() throws {
        try scheduleRelease.validate(); try calendarRelease.validate()
        try orderedOverrideEventSHA256s.forEach(ScheduleLimitsV1.digest)
        try ScheduleLimitsV1.digest(occurrenceClosureSHA256); try evaluatedRange.validate(); try budget.validate()
        guard workspaceID == scheduleRelease.workspaceID, workspaceID == calendarRelease.workspaceID,
              orderedOverrideEventSHA256s == orderedOverrideEventSHA256s.sorted(),
              Set(orderedOverrideEventSHA256s).count == orderedOverrideEventSHA256s.count,
              frontierSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else {
            throw ScheduleFailureV1.divergentReplay
        }
    }
    private var basis: Basis { .init(workspaceID: workspaceID, scheduleRelease: scheduleRelease,
        calendarRelease: calendarRelease, orderedOverrideEventSHA256s: orderedOverrideEventSHA256s,
        occurrenceClosureSHA256: occurrenceClosureSHA256, evaluatedRange: evaluatedRange, budget: budget) }
    private struct Basis: Codable { let workspaceID: WorkspaceID
        let scheduleRelease: ScheduleDefinitionReleaseReferenceV1
        let calendarRelease: ExceptionCalendarReleaseReferenceV1
        let orderedOverrideEventSHA256s: [String]; let occurrenceClosureSHA256: String
        let evaluatedRange: ScheduleLocalDateRangeV1; let budget: AdvancedScheduleGenerationBudgetV1 }
}

struct ScheduleChangePreviewV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let frontier: ScheduleChangeFrontierV1
    let proposedOverride: ScheduleOverrideEventV1?
    let effects: [ScheduleChangeEffectV1]
    let previewSHA256: String

    init(frontier: ScheduleChangeFrontierV1, proposedOverride: ScheduleOverrideEventV1?,
         effects: [ScheduleChangeEffectV1]) throws {
        schemaVersion = Self.schemaVersion; self.frontier = frontier; self.proposedOverride = proposedOverride
        self.effects = effects.sorted { $0.occurrenceID < $1.occurrenceID }
        previewSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            frontier: frontier, proposedOverride: proposedOverride, effects: self.effects))
        try validate()
    }
    func validate() throws {
        try frontier.validate(); try proposedOverride?.validate()
        try effects.forEach { try $0.occurrenceID.validate(); try $0.successorOccurrenceID?.validate()
            try $0.priorBasisSHA256.map(ScheduleLimitsV1.digest); try $0.resultingBasis?.validate()
            try $0.sourceOverrideEventSHA256.map(ScheduleLimitsV1.digest) }
        guard schemaVersion == Self.schemaVersion, effects == effects.sorted(by: { $0.occurrenceID < $1.occurrenceID }),
              Set(effects.map(\.occurrenceID)).count == effects.count,
              proposedOverride.map({ $0.workspaceID == frontier.workspaceID }) ?? true,
              previewSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else { throw ScheduleFailureV1.divergentReplay }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, frontier: frontier,
        proposedOverride: proposedOverride, effects: effects) }
    private struct Basis: Codable { let schemaVersion: Int; let frontier: ScheduleChangeFrontierV1
        let proposedOverride: ScheduleOverrideEventV1?; let effects: [ScheduleChangeEffectV1] }
}

struct ScheduleChangeReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let previewSHA256: String
    let committedFrontierSHA256: String
    let committedOverride: ScheduleOverrideEventReferenceV1?
    let canonicalMutationReceiptSHA256: String
    let committedAt: Date
    let receiptSHA256: String

    init(preview: ScheduleChangePreviewV1, mutationID: MutationIDV1,
         committedOverride: ScheduleOverrideEventReferenceV1?,
         canonicalMutationReceiptSHA256: String, committedAt: Date) throws {
        schemaVersion = Self.schemaVersion; workspaceID = preview.frontier.workspaceID; self.mutationID = mutationID
        previewSHA256 = preview.previewSHA256; committedFrontierSHA256 = preview.frontier.frontierSHA256
        self.committedOverride = committedOverride; self.canonicalMutationReceiptSHA256 = canonicalMutationReceiptSHA256
        self.committedAt = committedAt
        receiptSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID, mutationID: mutationID, previewSHA256: previewSHA256,
            committedFrontierSHA256: committedFrontierSHA256, committedOverride: committedOverride,
            canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256, committedAt: committedAt))
        try validate(preview: preview)
    }
    func validate(preview: ScheduleChangePreviewV1) throws {
        try preview.validate(); try ScheduleLimitsV1.digest(previewSHA256)
        try ScheduleLimitsV1.digest(committedFrontierSHA256); try committedOverride?.validate()
        try ScheduleLimitsV1.digest(canonicalMutationReceiptSHA256); try ScheduleLimitsV1.instant(committedAt)
        guard schemaVersion == Self.schemaVersion, workspaceID == preview.frontier.workspaceID,
              previewSHA256 == preview.previewSHA256,
              committedFrontierSHA256 == preview.frontier.frontierSHA256,
              committedOverride?.workspaceID == workspaceID || committedOverride == nil,
              committedOverride?.eventSHA256 == preview.proposedOverride?.eventSHA256,
              receiptSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else {
            throw ScheduleFailureV1.divergentReplay
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, workspaceID: workspaceID,
        mutationID: mutationID, previewSHA256: previewSHA256,
        committedFrontierSHA256: committedFrontierSHA256, committedOverride: committedOverride,
        canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256, committedAt: committedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID
        let mutationID: MutationIDV1; let previewSHA256: String; let committedFrontierSHA256: String
        let committedOverride: ScheduleOverrideEventReferenceV1?; let canonicalMutationReceiptSHA256: String
        let committedAt: Date }
}

enum ScheduleOccurrenceLineageV1 {
    static func addedOccurrenceID(scheduleDefinitionID: UUID, identityNamespaceID: UUID,
                                  overrideEvent: ScheduleOverrideEventV1) throws -> OccurrenceIDV1 {
        try overrideEvent.validate()
        guard overrideEvent.kind == .addOne else { throw ScheduleFailureV1.invalidValue }
        return try OccurrenceIDV1(scheduleDefinitionID: scheduleDefinitionID,
            identityNamespaceID: identityNamespaceID,
            nominalKey: "ADD_ONE|\(overrideEvent.target.nominalDate.canonicalString)|\(overrideEvent.eventSHA256)",
            predecessorOccurrenceID: nil, completionEventSHA256: nil)
    }

    static func validateHistoryImmutability(inputs: [ScheduleChangeOccurrenceInputV1],
                                            effects: [ScheduleChangeEffectV1]) throws {
        let effectByID = Dictionary(uniqueKeysWithValues: effects.map { ($0.occurrenceID, $0) })
        for input in inputs where input.isImmutableHistory {
            guard let effect = effectByID[input.occurrenceID], effect.disposition == .unchanged,
                  effect.priorBasisSHA256 == input.basis.basisSHA256,
                  effect.resultingBasis?.basisSHA256 == input.basis.basisSHA256 else {
                throw ScheduleFailureV1.invalidTransition
            }
        }
    }

    static func recurrenceRotationEffects(oldRelease: ScheduleDefinitionReleaseV1,
                                          newRelease: ScheduleDefinitionReleaseV1,
                                          oldBinding: AdvancedScheduleReleaseBindingV1,
                                          newBinding: AdvancedScheduleReleaseBindingV1,
                                          inputs: [ScheduleChangeOccurrenceInputV1]) throws -> [ScheduleChangeEffectV1] {
        try newRelease.validateSuccessor(of: oldRelease)
        try newBinding.validateSuccessor(of: oldBinding, oldRelease: oldRelease, newRelease: newRelease)
        guard oldBinding.recurrence != newBinding.recurrence,
              oldRelease.occurrenceIdentityNamespaceID != newRelease.occurrenceIdentityNamespaceID else {
            throw ScheduleFailureV1.invalidSuccessor
        }
        var effects: [ScheduleChangeEffectV1] = []
        for input in inputs.sorted(by: { $0.occurrenceID < $1.occurrenceID }) {
            try input.validate()
            if input.isImmutableHistory {
                effects.append(.init(occurrenceID: input.occurrenceID, successorOccurrenceID: nil,
                    disposition: .unchanged, priorBasisSHA256: input.basis.basisSHA256,
                    resultingBasis: input.basis, sourceOverrideEventSHA256: nil))
                continue
            }
            let successorID = try OccurrenceIDV1(scheduleDefinitionID: newRelease.scheduleDefinitionID,
                identityNamespaceID: newRelease.occurrenceIdentityNamespaceID,
                nominalKey: "\(input.basis.nominalDate.canonicalString)T\(input.basis.nominalWindow.stableKey)")
            let successorBasis = try TimeContextRule.freezeScheduleBasisV2(
                nominalDate: input.basis.nominalDate, effectiveDate: input.basis.effectiveDate,
                nominalWindow: input.basis.nominalWindow, effectiveWindow: input.basis.effectiveWindow,
                calendarRelease: newBinding.calendarRelease, timeBasis: newRelease.timeBasis,
                adjustmentReason: input.basis.adjustmentReason,
                predecessorBasisSHA256: input.basis.basisSHA256)
            effects.append(.init(occurrenceID: input.occurrenceID, successorOccurrenceID: successorID,
                disposition: .cancelled, priorBasisSHA256: input.basis.basisSHA256,
                resultingBasis: nil, sourceOverrideEventSHA256: nil))
            effects.append(.init(occurrenceID: successorID, successorOccurrenceID: nil,
                disposition: .created, priorBasisSHA256: nil,
                resultingBasis: successorBasis, sourceOverrideEventSHA256: nil))
        }
        try validateHistoryImmutability(inputs: inputs, effects: effects)
        return effects
    }
}
