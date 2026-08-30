import Foundation

// C51 closed, local-only schedule grammar and immutable exception-calendar authority.

enum ScheduleWeekdayV1: Int, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ScheduleLocalDateV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) throws {
        self.year = year; self.month = month; self.day = day
        try validate()
    }

    init(_ canonicalValue: String) throws {
        let parts = canonicalValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2,
              parts[2].count == 2, let year = Int(parts[0]),
              let month = Int(parts[1]), let day = Int(parts[2]) else {
            throw ScheduleFailureV1.invalidValue
        }
        self.year = year; self.month = month; self.day = day
        try validate()
        guard canonicalString == canonicalValue else { throw ScheduleFailureV1.invalidValue }
    }

    var canonicalString: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var stableKey: Int { year * 10_000 + month * 100 + day }

    func validate() throws {
        guard (1...9_999).contains(year), (1...12).contains(month),
              (1...31).contains(day) else { throw ScheduleFailureV1.invalidValue }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        guard let utc = TimeZone(secondsFromGMT: 0) else { throw ScheduleFailureV1.invalidValue }
        calendar.timeZone = utc
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                                        year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { throw ScheduleFailureV1.invalidValue }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw ScheduleFailureV1.invalidValue
        }
    }

    func weekday() throws -> ScheduleWeekdayV1 {
        try validate()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        guard let utc = TimeZone(secondsFromGMT: 0) else { throw ScheduleFailureV1.invalidValue }
        calendar.timeZone = utc
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            throw ScheduleFailureV1.invalidValue
        }
        guard let value = ScheduleWeekdayV1(rawValue: calendar.component(.weekday, from: date)) else {
            throw ScheduleFailureV1.invalidValue
        }
        return value
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableKey < rhs.stableKey }
}

struct ScheduleLocalDateRangeV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let startsOn: ScheduleLocalDateV1
    let endsOn: ScheduleLocalDateV1
    func validate() throws { try startsOn.validate(); try endsOn.validate(); guard startsOn <= endsOn else { throw ScheduleFailureV1.invalidValue } }
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.startsOn == rhs.startsOn ? lhs.endsOn < rhs.endsOn : lhs.startsOn < rhs.startsOn
    }
    func contains(_ date: ScheduleLocalDateV1) -> Bool { startsOn <= date && date <= endsOn }
}

enum MissingDayPolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case skipWithReason = "SKIP_WITH_REASON"
    case lastValidDay = "LAST_VALID_DAY"
    case requireManualResolution = "REQUIRE_MANUAL_RESOLUTION"
}

enum ScheduleWeekdayOrdinalV1: String, Codable, CaseIterable, Hashable, Sendable {
    case first = "FIRST", second = "SECOND", third = "THIRD", fourth = "FOURTH", last = "LAST"
}

enum CompletionRelativeCalendarUnitV1: String, Codable, CaseIterable, Hashable, Sendable {
    case days = "DAYS", weeks = "WEEKS", months = "MONTHS", years = "YEARS"
}

enum BusinessDayAdjustmentPolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case nextIncludedDay = "NEXT_INCLUDED_DAY"
    case previousIncludedDay = "PREVIOUS_INCLUDED_DAY"
    case skipWithReason = "SKIP_WITH_REASON"
    case requireManualResolution = "REQUIRE_MANUAL_RESOLUTION"
}

enum CompletionGapPolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case pauseChain = "PAUSE_CHAIN"
    case anchorToNominalAfterExplicitSkip = "ANCHOR_TO_NOMINAL_AFTER_EXPLICIT_SKIP"
    case requireManualAnchor = "REQUIRE_MANUAL_ANCHOR"
}

enum AdvancedRecurrenceRuleV1: Codable, Equatable, Hashable, Sendable {
    case daily(interval: Int)
    case weekly(interval: Int, weekdays: [ScheduleWeekdayV1])
    case monthlyDay(interval: Int, day: Int, missingDayPolicy: MissingDayPolicyV1)
    case monthlyWeekday(interval: Int, ordinal: ScheduleWeekdayOrdinalV1, weekday: ScheduleWeekdayV1)
    case yearly(interval: Int, month: Int, day: Int, missingDayPolicy: MissingDayPolicyV1)
    case completionRelative(interval: Int, unit: CompletionRelativeCalendarUnitV1,
                            gapPolicy: CompletionGapPolicyV1)

    func validate() throws {
        switch self {
        case .daily(let interval):
            guard (1...365).contains(interval) else { throw ScheduleFailureV1.invalidValue }
        case .weekly(let interval, let weekdays):
            guard (1...52).contains(interval), !weekdays.isEmpty,
                  weekdays == weekdays.sorted(), Set(weekdays).count == weekdays.count else {
                throw ScheduleFailureV1.invalidValue
            }
        case .monthlyDay(let interval, let day, _):
            guard (1...12).contains(interval), (1...31).contains(day) else { throw ScheduleFailureV1.invalidValue }
        case .monthlyWeekday(let interval, _, _):
            guard (1...12).contains(interval) else { throw ScheduleFailureV1.invalidValue }
        case .yearly(let interval, let month, let day, _):
            guard (1...10).contains(interval), (1...12).contains(month), (1...31).contains(day) else {
                throw ScheduleFailureV1.invalidValue
            }
        case .completionRelative(let interval, _, _):
            guard (1...3_650).contains(interval) else { throw ScheduleFailureV1.invalidValue }
        }
    }
}

struct AdvancedScheduleGenerationBudgetV1: Codable, Equatable, Hashable, Sendable {
    static let lookaheadDays = 400
    static let reconciliationBackfillDays = 90
    static let maximumGeneratedPerSchedule = 512
    static let maximumActiveUpcomingPerWorkspace = 10_000

    let lookaheadDays: Int
    let reconciliationBackfillDays: Int
    let maximumGeneratedPerSchedule: Int
    let maximumActiveUpcomingPerWorkspace: Int

    init(lookaheadDays: Int = Self.lookaheadDays,
         reconciliationBackfillDays: Int = Self.reconciliationBackfillDays,
         maximumGeneratedPerSchedule: Int = Self.maximumGeneratedPerSchedule,
         maximumActiveUpcomingPerWorkspace: Int = Self.maximumActiveUpcomingPerWorkspace) throws {
        self.lookaheadDays = lookaheadDays; self.reconciliationBackfillDays = reconciliationBackfillDays
        self.maximumGeneratedPerSchedule = maximumGeneratedPerSchedule
        self.maximumActiveUpcomingPerWorkspace = maximumActiveUpcomingPerWorkspace
        try validate()
    }

    func validate() throws {
        guard lookaheadDays == Self.lookaheadDays,
              reconciliationBackfillDays == Self.reconciliationBackfillDays,
              maximumGeneratedPerSchedule == Self.maximumGeneratedPerSchedule,
              maximumActiveUpcomingPerWorkspace == Self.maximumActiveUpcomingPerWorkspace else {
            throw ScheduleFailureV1.limitExceeded
        }
    }

    func validate(generatedCount: Int, activeUpcomingWorkspaceCount: Int) throws {
        try validate()
        guard generatedCount <= maximumGeneratedPerSchedule,
              activeUpcomingWorkspaceCount <= maximumActiveUpcomingPerWorkspace,
              generatedCount >= 0, activeUpcomingWorkspaceCount >= 0 else {
            throw ScheduleFailureV1.limitExceeded
        }
    }
}

struct ExceptionCalendarReleaseReferenceV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let calendarID: UUID
    let releaseID: UUID
    let revision: UInt64
    let releaseSHA256: String
    func validate() throws {
        try ScheduleLimitsV1.id(calendarID); try ScheduleLimitsV1.id(releaseID)
        try ScheduleLimitsV1.revision(revision); try ScheduleLimitsV1.digest(releaseSHA256)
    }
}

enum ExceptionCalendarDateDispositionV1: String, Codable, Hashable, Sendable {
    case includedOverride = "INCLUDED_OVERRIDE"
    case excludedDate = "EXCLUDED_DATE"
    case excludedRange = "EXCLUDED_RANGE"
    case baseIncludedWeekday = "BASE_INCLUDED_WEEKDAY"
    case baseExcludedWeekday = "BASE_EXCLUDED_WEEKDAY"
}

struct ExceptionCalendarReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumExcludedDates = 366
    static let maximumExcludedRanges = 32
    static let maximumIncludedOverrideDates = 366

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let calendarID: UUID
    let releaseID: UUID
    let name: String
    let calendar: ScheduleCalendarIdentifierV1
    let ianaTimeZoneIdentifier: String
    let effectiveRange: ScheduleLocalDateRangeV1
    let baseIncludedWeekdays: [ScheduleWeekdayV1]
    let excludedDates: [ScheduleLocalDateV1]
    let excludedRanges: [ScheduleLocalDateRangeV1]
    let includedOverrideDates: [ScheduleLocalDateV1]
    let supersedesReleaseID: UUID?
    let predecessorReleaseSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let authoredBy: ActorSnapshotV1
    let authoredAt: Date
    let releaseSHA256: String

    init(workspaceID: WorkspaceID, calendarID: UUID, releaseID: UUID, name: String,
         ianaTimeZoneIdentifier: String, effectiveRange: ScheduleLocalDateRangeV1,
         baseIncludedWeekdays: [ScheduleWeekdayV1], excludedDates: [ScheduleLocalDateV1] = [],
         excludedRanges: [ScheduleLocalDateRangeV1] = [], includedOverrideDates: [ScheduleLocalDateV1] = [],
         supersedesReleaseID: UUID? = nil, predecessorReleaseSHA256: String? = nil,
         revision: UInt64, mutationID: MutationIDV1, authoredBy: ActorSnapshotV1, authoredAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.calendarID = calendarID
        self.releaseID = releaseID; self.name = name; calendar = .gregorianV1
        self.ianaTimeZoneIdentifier = ianaTimeZoneIdentifier; self.effectiveRange = effectiveRange
        self.baseIncludedWeekdays = baseIncludedWeekdays.sorted(); self.excludedDates = excludedDates.sorted()
        self.excludedRanges = excludedRanges.sorted(); self.includedOverrideDates = includedOverrideDates.sorted()
        self.supersedesReleaseID = supersedesReleaseID; self.predecessorReleaseSHA256 = predecessorReleaseSHA256
        self.revision = revision; self.mutationID = mutationID; self.authoredBy = authoredBy; self.authoredAt = authoredAt
        releaseSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID, calendarID: calendarID, releaseID: releaseID, name: name,
            calendar: .gregorianV1, ianaTimeZoneIdentifier: ianaTimeZoneIdentifier,
            effectiveRange: effectiveRange, baseIncludedWeekdays: self.baseIncludedWeekdays,
            excludedDates: self.excludedDates, excludedRanges: self.excludedRanges,
            includedOverrideDates: self.includedOverrideDates, supersedesReleaseID: supersedesReleaseID,
            predecessorReleaseSHA256: predecessorReleaseSHA256, revision: revision,
            mutationID: mutationID, authoredBy: authoredBy, authoredAt: authoredAt))
        try validate()
    }

    var reference: ExceptionCalendarReleaseReferenceV1 {
        .init(workspaceID: workspaceID, calendarID: calendarID, releaseID: releaseID,
              revision: revision, releaseSHA256: releaseSHA256)
    }

    func validate() throws {
        try ScheduleLimitsV1.id(calendarID); try ScheduleLimitsV1.id(releaseID); try ScheduleLimitsV1.token(name)
        try ScheduleLimitsV1.token(ianaTimeZoneIdentifier); try effectiveRange.validate()
        try excludedDates.forEach { try $0.validate() }; try excludedRanges.forEach { try $0.validate() }
        try includedOverrideDates.forEach { try $0.validate() }; try authoredBy.validate(); try ScheduleLimitsV1.instant(authoredAt)
        guard schemaVersion == Self.schemaVersion, calendar == .gregorianV1,
              TimeZone.knownTimeZoneIdentifiers.contains(ianaTimeZoneIdentifier),
              !baseIncludedWeekdays.isEmpty, baseIncludedWeekdays == baseIncludedWeekdays.sorted(),
              Set(baseIncludedWeekdays).count == baseIncludedWeekdays.count,
              excludedDates.count <= Self.maximumExcludedDates,
              excludedRanges.count <= Self.maximumExcludedRanges,
              includedOverrideDates.count <= Self.maximumIncludedOverrideDates,
              excludedDates == excludedDates.sorted(), Set(excludedDates).count == excludedDates.count,
              excludedRanges == excludedRanges.sorted(), Set(excludedRanges).count == excludedRanges.count,
              includedOverrideDates == includedOverrideDates.sorted(), Set(includedOverrideDates).count == includedOverrideDates.count,
              excludedDates.allSatisfy(effectiveRange.contains),
              excludedRanges.allSatisfy({ effectiveRange.contains($0.startsOn) && effectiveRange.contains($0.endsOn) }),
              includedOverrideDates.allSatisfy(effectiveRange.contains),
              revision > 0, (revision == 1) == (supersedesReleaseID == nil && predecessorReleaseSHA256 == nil),
              supersedesReleaseID != releaseID,
              predecessorReleaseSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              authoredBy.workspaceID == workspaceID,
              releaseSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else { throw ScheduleFailureV1.invalidDigest }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validate(); try validate()
        guard predecessor.workspaceID == workspaceID, predecessor.calendarID == calendarID,
              predecessor.revision < UInt64.max, revision == predecessor.revision + 1,
              supersedesReleaseID == predecessor.releaseID,
              predecessorReleaseSHA256 == predecessor.releaseSHA256,
              releaseID != predecessor.releaseID, mutationID != predecessor.mutationID else {
            throw ScheduleFailureV1.invalidSuccessor
        }
    }

    func disposition(on date: ScheduleLocalDateV1) throws -> ExceptionCalendarDateDispositionV1 {
        try validate(); try date.validate()
        guard effectiveRange.contains(date) else { throw ScheduleFailureV1.staleBasis }
        if includedOverrideDates.contains(date) { return .includedOverride }
        if excludedDates.contains(date) { return .excludedDate }
        if excludedRanges.contains(where: { $0.contains(date) }) { return .excludedRange }
        return baseIncludedWeekdays.contains(try date.weekday()) ? .baseIncludedWeekday : .baseExcludedWeekday
    }

    func isIncluded(_ date: ScheduleLocalDateV1) throws -> Bool {
        switch try disposition(on: date) {
        case .includedOverride, .baseIncludedWeekday: return true
        case .excludedDate, .excludedRange, .baseExcludedWeekday: return false
        }
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, workspaceID: workspaceID,
        calendarID: calendarID, releaseID: releaseID, name: name, calendar: calendar,
        ianaTimeZoneIdentifier: ianaTimeZoneIdentifier, effectiveRange: effectiveRange,
        baseIncludedWeekdays: baseIncludedWeekdays, excludedDates: excludedDates,
        excludedRanges: excludedRanges, includedOverrideDates: includedOverrideDates,
        supersedesReleaseID: supersedesReleaseID, predecessorReleaseSHA256: predecessorReleaseSHA256,
        revision: revision, mutationID: mutationID, authoredBy: authoredBy, authoredAt: authoredAt) }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let calendarID: UUID
        let releaseID: UUID; let name: String; let calendar: ScheduleCalendarIdentifierV1
        let ianaTimeZoneIdentifier: String; let effectiveRange: ScheduleLocalDateRangeV1
        let baseIncludedWeekdays: [ScheduleWeekdayV1]; let excludedDates: [ScheduleLocalDateV1]
        let excludedRanges: [ScheduleLocalDateRangeV1]; let includedOverrideDates: [ScheduleLocalDateV1]
        let supersedesReleaseID: UUID?; let predecessorReleaseSHA256: String?; let revision: UInt64
        let mutationID: MutationIDV1; let authoredBy: ActorSnapshotV1; let authoredAt: Date }
}

enum AllDaysCompatibilityCalendarV1 {
    static let schemaVersion = 1
    static let basisID = ScheduleLimitsV1.allDaysCalendarBasisID
    static let calendarID = UUID(uuid: (0xa1,0x1d,0xa1,0x11,0xda,0x11,0x4d,0xa1,0x8d,0xa1,0xa1,0x1d,0xa1,0x1d,0xa1,0x11))
    static let releaseID = UUID(uuid: (0xa1,0x1d,0xa1,0x12,0xda,0x11,0x4d,0xa1,0x8d,0xa1,0xa1,0x1d,0xa1,0x1d,0xa1,0x12))
    static let revision: UInt64 = 1
    static let calendar: ScheduleCalendarIdentifierV1 = .gregorianV1
    static let ianaTimeZoneIdentifier = "Etc/UTC"
    static let effectiveStartsOn = "0001-01-01"
    static let effectiveEndsOn = "9999-12-31"
    static let includedWeekdays = ScheduleWeekdayV1.allCases.sorted()
    static let virtualReleaseCanonicalBasis = [String(schemaVersion), basisID,
        calendarID.uuidString.lowercased(), releaseID.uuidString.lowercased(), String(revision),
        calendar.rawValue, ianaTimeZoneIdentifier, effectiveStartsOn, effectiveEndsOn,
        includedWeekdays.map { String($0.rawValue) }.joined(separator: ",")].joined(separator: "|")
    static let releaseSHA256 = KernelCanonicalHashV1.sha256(Data(virtualReleaseCanonicalBasis.utf8))
    static func reference(workspaceID: WorkspaceID) -> ExceptionCalendarReleaseReferenceV1 {
        .init(workspaceID: workspaceID, calendarID: calendarID, releaseID: releaseID,
              revision: revision, releaseSHA256: releaseSHA256)
    }
    static func validate(reference: ExceptionCalendarReleaseReferenceV1) throws {
        try reference.validate()
        guard reference.calendarID == calendarID, reference.releaseID == releaseID,
              reference.revision == revision, reference.releaseSHA256 == releaseSHA256,
              KernelCanonicalHashV1.validSHA256(releaseSHA256) else {
            throw ScheduleFailureV1.invalidDigest
        }
    }
    static func isImplicitCompatibilityBinding(for release: ScheduleDefinitionReleaseV1) throws -> Bool {
        try release.validate()
        return release.timeBasis.calendarBasisID == basisID
            && release.timeBasis.calendar == calendar
    }
    /// The virtual release is interpretation authority only. Legacy schedules
    /// require no fabricated persistent calendar row and preserve C28 identity.
    static let requiresPersistedReleaseRow = false
    static let changesExistingOccurrenceIDsOrDates = false
}

/// Canonical C51 configuration embedded in ScheduleRecurrenceV1 so the existing
/// immutable C28 release row, backup, replay, and writer remain its sole owner.
struct AdvancedScheduleConfigurationV1: Codable, Equatable, Hashable, Sendable {
    let recurrence: AdvancedRecurrenceRuleV1
    let calendarRelease: ExceptionCalendarReleaseReferenceV1
    let businessDayAdjustmentPolicy: BusinessDayAdjustmentPolicyV1
    func validate() throws { try recurrence.validate(); try calendarRelease.validate() }
}

/// Noncanonical derived view. Its only initializer extracts configuration from
/// an already validated immutable schedule release; it cannot outlive or
/// contradict the release as independent truth.
struct AdvancedScheduleReleaseBindingV1: Equatable, Sendable {
    let scheduleRelease: ScheduleDefinitionReleaseReferenceV1
    let configuration: AdvancedScheduleConfigurationV1

    init(_ release: ScheduleDefinitionReleaseV1) throws {
        try release.validate()
        guard case .advanced(let configuration) = release.recurrence else {
            throw ScheduleFailureV1.invalidValue
        }
        scheduleRelease = try .init(release); self.configuration = configuration
        try validate()
    }

    var recurrence: AdvancedRecurrenceRuleV1 { configuration.recurrence }
    var calendarRelease: ExceptionCalendarReleaseReferenceV1 { configuration.calendarRelease }
    var businessDayAdjustmentPolicy: BusinessDayAdjustmentPolicyV1 {
        configuration.businessDayAdjustmentPolicy
    }

    func validate() throws {
        try scheduleRelease.validate(); try configuration.validate()
        guard scheduleRelease.workspaceID == calendarRelease.workspaceID else { throw ScheduleFailureV1.wrongWorkspace }
    }

    /// Calendar release changes adjust bases without changing IDs. Recurrence
    /// grammar changes require the C28 successor release to rotate its namespace.
    func validateSuccessor(of predecessor: Self,
                           oldRelease: ScheduleDefinitionReleaseV1,
                           newRelease: ScheduleDefinitionReleaseV1) throws {
        try predecessor.validate(); try validate(); try newRelease.validateSuccessor(of: oldRelease)
        guard predecessor.scheduleRelease == (try ScheduleDefinitionReleaseReferenceV1(oldRelease)),
              scheduleRelease == (try ScheduleDefinitionReleaseReferenceV1(newRelease)),
              oldRelease.recurrence == .advanced(predecessor.configuration),
              newRelease.recurrence == .advanced(configuration) else {
            throw ScheduleFailureV1.staleBasis
        }
        let recurrenceChanged = recurrence != predecessor.recurrence
        guard recurrenceChanged ==
                (newRelease.occurrenceIdentityNamespaceID != oldRelease.occurrenceIdentityNamespaceID) else {
            throw ScheduleFailureV1.invalidSuccessor
        }
    }

}

enum ScheduleBasisAdjustmentReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case none = "NONE", includedOverride = "INCLUDED_OVERRIDE", excludedDate = "EXCLUDED_DATE"
    case excludedRange = "EXCLUDED_RANGE", nextIncludedDay = "NEXT_INCLUDED_DAY"
    case previousIncludedDay = "PREVIOUS_INCLUDED_DAY", explicitMove = "EXPLICIT_MOVE"
    case explicitSkip = "EXPLICIT_SKIP", manualResolution = "MANUAL_RESOLUTION"
}

struct OccurrenceScheduleBasisV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let nominalDate: ScheduleLocalDateV1
    let effectiveDate: ScheduleLocalDateV1?
    let nominalWindow: ScheduleLocalAnchorV1
    let effectiveWindow: ScheduleLocalAnchorV1?
    let calendarRelease: ExceptionCalendarReleaseReferenceV1
    let ianaTimeZoneIdentifier: String
    let timeZoneRuleSetVersion: String
    let timeZoneRuleSetSHA256: String
    let ambiguousTimePolicy: AmbiguousLocalTimePolicyV1
    let nonexistentTimePolicy: NonexistentLocalTimePolicyV1
    let resolvedAtUTC: Date?
    let resolvedUTCOffsetSeconds: Int?
    let localTimeDisposition: LocalTimeDispositionV1
    let adjustmentReason: ScheduleBasisAdjustmentReasonV1
    let sourceOverrideEventSHA256: String?
    let predecessorBasisSHA256: String?
    let basisSHA256: String

    init(nominalDate: ScheduleLocalDateV1, effectiveDate: ScheduleLocalDateV1?,
         nominalWindow: ScheduleLocalAnchorV1, effectiveWindow: ScheduleLocalAnchorV1?,
         calendarRelease: ExceptionCalendarReleaseReferenceV1, timeBasis: FrozenScheduleTimeBasisV1,
         resolvedAtUTC: Date?, resolvedUTCOffsetSeconds: Int?,
         localTimeDisposition: LocalTimeDispositionV1,
         adjustmentReason: ScheduleBasisAdjustmentReasonV1 = .none,
         sourceOverrideEventSHA256: String? = nil, predecessorBasisSHA256: String? = nil) throws {
        schemaVersion = Self.schemaVersion; self.nominalDate = nominalDate; self.effectiveDate = effectiveDate
        self.nominalWindow = nominalWindow; self.effectiveWindow = effectiveWindow; self.calendarRelease = calendarRelease
        ianaTimeZoneIdentifier = timeBasis.ianaTimeZoneIdentifier
        timeZoneRuleSetVersion = timeBasis.timeZoneRuleSetVersion
        timeZoneRuleSetSHA256 = timeBasis.timeZoneRuleSetSHA256
        ambiguousTimePolicy = timeBasis.ambiguousTimePolicy; nonexistentTimePolicy = timeBasis.nonexistentTimePolicy
        self.resolvedAtUTC = resolvedAtUTC; self.resolvedUTCOffsetSeconds = resolvedUTCOffsetSeconds
        self.localTimeDisposition = localTimeDisposition; self.adjustmentReason = adjustmentReason
        self.sourceOverrideEventSHA256 = sourceOverrideEventSHA256; self.predecessorBasisSHA256 = predecessorBasisSHA256
        basisSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            nominalDate: nominalDate, effectiveDate: effectiveDate, nominalWindow: nominalWindow,
            effectiveWindow: effectiveWindow, calendarRelease: calendarRelease,
            ianaTimeZoneIdentifier: timeBasis.ianaTimeZoneIdentifier,
            timeZoneRuleSetVersion: timeBasis.timeZoneRuleSetVersion,
            timeZoneRuleSetSHA256: timeBasis.timeZoneRuleSetSHA256,
            ambiguousTimePolicy: timeBasis.ambiguousTimePolicy,
            nonexistentTimePolicy: timeBasis.nonexistentTimePolicy, resolvedAtUTC: resolvedAtUTC,
            resolvedUTCOffsetSeconds: resolvedUTCOffsetSeconds, localTimeDisposition: localTimeDisposition,
            adjustmentReason: adjustmentReason, sourceOverrideEventSHA256: sourceOverrideEventSHA256,
            predecessorBasisSHA256: predecessorBasisSHA256))
        try validate()
    }

    func validate() throws {
        try nominalDate.validate(); try effectiveDate?.validate(); try nominalWindow.validate(); try effectiveWindow?.validate()
        try calendarRelease.validate(); try ScheduleLimitsV1.token(ianaTimeZoneIdentifier)
        try ScheduleLimitsV1.token(timeZoneRuleSetVersion); try ScheduleLimitsV1.digest(timeZoneRuleSetSHA256)
        try resolvedAtUTC.map(ScheduleLimitsV1.instant); try sourceOverrideEventSHA256.map(ScheduleLimitsV1.digest)
        try predecessorBasisSHA256.map(ScheduleLimitsV1.digest)
        guard schemaVersion == Self.schemaVersion,
              (effectiveDate == nil) == (effectiveWindow == nil),
              (resolvedAtUTC == nil) == (resolvedUTCOffsetSeconds == nil),
              (resolvedAtUTC == nil) == (effectiveDate == nil),
              resolvedUTCOffsetSeconds.map({ (-64_800...64_800).contains($0) }) ?? true,
              basisSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else { throw ScheduleFailureV1.invalidDigest }
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, nominalDate: nominalDate,
        effectiveDate: effectiveDate, nominalWindow: nominalWindow, effectiveWindow: effectiveWindow,
        calendarRelease: calendarRelease, ianaTimeZoneIdentifier: ianaTimeZoneIdentifier,
        timeZoneRuleSetVersion: timeZoneRuleSetVersion, timeZoneRuleSetSHA256: timeZoneRuleSetSHA256,
        ambiguousTimePolicy: ambiguousTimePolicy, nonexistentTimePolicy: nonexistentTimePolicy,
        resolvedAtUTC: resolvedAtUTC, resolvedUTCOffsetSeconds: resolvedUTCOffsetSeconds,
        localTimeDisposition: localTimeDisposition, adjustmentReason: adjustmentReason,
        sourceOverrideEventSHA256: sourceOverrideEventSHA256, predecessorBasisSHA256: predecessorBasisSHA256) }
    private struct Basis: Codable { let schemaVersion: Int; let nominalDate: ScheduleLocalDateV1
        let effectiveDate: ScheduleLocalDateV1?; let nominalWindow: ScheduleLocalAnchorV1
        let effectiveWindow: ScheduleLocalAnchorV1?; let calendarRelease: ExceptionCalendarReleaseReferenceV1
        let ianaTimeZoneIdentifier: String; let timeZoneRuleSetVersion: String; let timeZoneRuleSetSHA256: String
        let ambiguousTimePolicy: AmbiguousLocalTimePolicyV1; let nonexistentTimePolicy: NonexistentLocalTimePolicyV1
        let resolvedAtUTC: Date?; let resolvedUTCOffsetSeconds: Int?; let localTimeDisposition: LocalTimeDispositionV1
        let adjustmentReason: ScheduleBasisAdjustmentReasonV1; let sourceOverrideEventSHA256: String?
        let predecessorBasisSHA256: String? }
}
