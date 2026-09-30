import Foundation

@MainActor protocol ScheduleExceptionProjectingV1: AnyObject {
    func preview(definition: ScheduleDefinitionReleaseV1,
                 binding: AdvancedScheduleReleaseBindingV1,
                 calendar: ExceptionCalendarReleaseV1,
                 existingOverrideEvents: [ScheduleOverrideEventV1],
                 proposedOverride: ScheduleOverrideEventV1?,
                 occurrences: [ScheduleChangeOccurrenceInputV1],
                 evaluatedRange: ScheduleLocalDateRangeV1,
                 activeUpcomingWorkspaceCount: Int) throws -> ScheduleChangePreviewV1
    func validateCommit(preview: ScheduleChangePreviewV1,
                        currentFrontier: ScheduleChangeFrontierV1) throws
}

@MainActor final class ScheduleExceptionCoordinatorV1 {
    private let projector: any ScheduleExceptionProjectingV1
    init(projector: any ScheduleExceptionProjectingV1) { self.projector = projector }

    func preview(definition: ScheduleDefinitionReleaseV1,
                 binding: AdvancedScheduleReleaseBindingV1,
                 calendar: ExceptionCalendarReleaseV1,
                 existingOverrideEvents: [ScheduleOverrideEventV1],
                 proposedOverride: ScheduleOverrideEventV1?,
                 occurrences: [ScheduleChangeOccurrenceInputV1],
                 evaluatedRange: ScheduleLocalDateRangeV1,
                 activeUpcomingWorkspaceCount: Int) throws -> ScheduleChangePreviewV1 {
        try projector.preview(definition: definition, binding: binding, calendar: calendar,
                              existingOverrideEvents: existingOverrideEvents,
                              proposedOverride: proposedOverride, occurrences: occurrences,
                              evaluatedRange: evaluatedRange,
                              activeUpcomingWorkspaceCount: activeUpcomingWorkspaceCount)
    }

    func validateCommit(preview: ScheduleChangePreviewV1,
                        currentFrontier: ScheduleChangeFrontierV1) throws {
        try projector.validateCommit(preview: preview, currentFrontier: currentFrontier)
    }
}

enum ScheduleExceptionProjectionEngineV1 {
    static func preview(definition: ScheduleDefinitionReleaseV1,
                        binding: AdvancedScheduleReleaseBindingV1,
                        calendar: ExceptionCalendarReleaseV1,
                        existingOverrideEvents: [ScheduleOverrideEventV1],
                        proposedOverride: ScheduleOverrideEventV1?,
                        occurrences: [ScheduleChangeOccurrenceInputV1],
                        evaluatedRange: ScheduleLocalDateRangeV1,
                        activeUpcomingWorkspaceCount: Int) throws -> ScheduleChangePreviewV1 {
        try definition.validate(); try binding.validate(); try calendar.validate(); try evaluatedRange.validate()
        let releaseReference = try ScheduleDefinitionReleaseReferenceV1(definition)
        guard binding.scheduleRelease == releaseReference,
              binding.calendarRelease == calendar.reference,
              occurrences.allSatisfy({ $0.basis.calendarRelease == calendar.reference }),
              Set(occurrences.map(\.occurrenceID)).count == occurrences.count else {
            throw ScheduleFailureV1.staleBasis
        }
        try occurrences.forEach { try $0.validate() }
        try ScheduleOverridePrecedenceV1.validateClosure(existingOverrideEvents,
                                                         for: releaseReference)
        let budget = try AdvancedScheduleGenerationBudgetV1()
        try budget.validate(generatedCount: occurrences.count,
                            activeUpcomingWorkspaceCount: activeUpcomingWorkspaceCount)
        if let proposedOverride {
            guard proposedOverride.scheduleRelease == releaseReference else { throw ScheduleFailureV1.staleBasis }
            try ScheduleOverridePrecedenceV1.validateExpectedFrontier(proposedOverride,
                                                                      against: existingOverrideEvents)
            if proposedOverride.kind != .addOne,
               proposedOverride.scope == .thisOccurrence,
               occurrences.contains(where: { $0.occurrenceID == proposedOverride.target.occurrenceID
                   && $0.isImmutableHistory }) {
                throw ScheduleFailureV1.invalidTransition
            }
        }
        let closureSHA256 = try ScheduleCanonicalCodecV1.sha256(OccurrenceClosure(values:
            occurrences.sorted { $0.occurrenceID < $1.occurrenceID }))
        let frontier = try ScheduleChangeFrontierV1(workspaceID: definition.workspaceID,
            scheduleRelease: releaseReference, calendarRelease: calendar.reference,
            overrideEvents: existingOverrideEvents, occurrenceClosureSHA256: closureSHA256,
            evaluatedRange: evaluatedRange, budget: budget)
        let resolutionEvents = existingOverrideEvents + (proposedOverride.map { [$0] } ?? [])
        var effects: [ScheduleChangeEffectV1] = []
        for input in occurrences.sorted(by: { $0.occurrenceID < $1.occurrenceID }) {
            if input.isImmutableHistory {
                effects.append(.init(occurrenceID: input.occurrenceID, successorOccurrenceID: nil,
                    disposition: .unchanged, priorBasisSHA256: input.basis.basisSHA256,
                    resultingBasis: input.basis, sourceOverrideEventSHA256: nil))
                continue
            }
            let resolution = try ScheduleOverridePrecedenceV1.resolve(occurrenceID: input.occurrenceID,
                nominalDate: input.basis.nominalDate, nominalWindow: input.basis.nominalWindow,
                scheduleRelease: releaseReference,
                calendar: calendar, adjustmentPolicy: binding.businessDayAdjustmentPolicy,
                events: resolutionEvents)
            let resultingBasis = try TimeContextRule.freezeScheduleBasisV2(
                nominalDate: input.basis.nominalDate, effectiveDate: resolution.effectiveDate,
                nominalWindow: input.basis.nominalWindow, effectiveWindow: resolution.effectiveWindow,
                calendarRelease: calendar.reference, timeBasis: definition.timeBasis,
                adjustmentReason: resolution.adjustmentReason,
                sourceOverrideEventSHA256: resolution.event?.eventSHA256,
                predecessorBasisSHA256: input.basis.basisSHA256)
            let disposition: ScheduleChangeDispositionV1
            if resolution.requiresManualResolution { disposition = .requiresManualResolution }
            else if resolution.effectiveDate == nil { disposition = .skipped }
            else if resultingBasis.effectiveDate != input.basis.effectiveDate
                        || resultingBasis.effectiveWindow != input.basis.effectiveWindow { disposition = .moved }
            else { disposition = .unchanged }
            effects.append(.init(occurrenceID: input.occurrenceID, successorOccurrenceID: nil,
                disposition: disposition, priorBasisSHA256: input.basis.basisSHA256,
                resultingBasis: resultingBasis,
                sourceOverrideEventSHA256: resolution.event?.eventSHA256))
        }
        if let event = proposedOverride, event.kind == .addOne,
           let date = event.replacementDate, let window = event.replacementWindow {
            let occurrenceID = try ScheduleOccurrenceLineageV1.addedOccurrenceID(
                scheduleDefinitionID: definition.scheduleDefinitionID,
                identityNamespaceID: definition.occurrenceIdentityNamespaceID, overrideEvent: event)
            guard !occurrences.contains(where: { $0.occurrenceID == occurrenceID }) else {
                throw ScheduleFailureV1.divergentReplay
            }
            let basis = try TimeContextRule.freezeScheduleBasisV2(nominalDate: event.target.nominalDate,
                effectiveDate: date, nominalWindow: window, effectiveWindow: window,
                calendarRelease: calendar.reference, timeBasis: definition.timeBasis,
                adjustmentReason: .none, sourceOverrideEventSHA256: event.eventSHA256)
            effects.append(.init(occurrenceID: occurrenceID, successorOccurrenceID: nil,
                disposition: .created, priorBasisSHA256: nil, resultingBasis: basis,
                sourceOverrideEventSHA256: event.eventSHA256))
        }
        try ScheduleOccurrenceLineageV1.validateHistoryImmutability(inputs: occurrences, effects: effects)
        return try .init(frontier: frontier, proposedOverride: proposedOverride, effects: effects)
    }

    static func validateCommit(preview: ScheduleChangePreviewV1,
                               currentFrontier: ScheduleChangeFrontierV1) throws {
        try preview.validate(); try currentFrontier.validate()
        guard preview.frontier == currentFrontier else { throw ScheduleFailureV1.staleBasis }
    }

    private struct OccurrenceClosure: Codable { let values: [ScheduleChangeOccurrenceInputV1] }
}

enum C34RouteAdoptionBoundary_ScheduleExceptionCoordinatorV1 {
    static let scheduleDestination = NavigationDestinationV1.scheduleOccurrence
    static let canonicalTargetType = NavigationTargetV1.self
    static let restorationIsReadOnly = true
}
