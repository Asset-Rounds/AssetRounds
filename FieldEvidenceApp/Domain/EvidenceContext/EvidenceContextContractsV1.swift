import CryptoKit
import Foundation

enum EvidenceContextFailureV1: Error, Equatable {
    case invalidIdentity
    case invalidValue
    case invalidDigest
    case incompatibleVersion
    case wrongWorkspace
    case predecessorMismatch
    case referenceMismatch
    case duplicateIdentity
    case unorderedValue
    case arithmeticOverflow
    case staleRevision
    case nonCanonicalEncoding
}

enum C31LightingEvidenceContextBoundaryV1 {
    static let contextIsUserObservedOrOfflineDerived = true
    static let solarContextDoesNotProveLightingCondition = true
    static let contextDigestIsPreservedInHistoricProjection = true
}

enum EvidenceContextLimitsV1 {
    static let maximumTokenBytes = 160
    static let maximumMismatchReasons = 8
    static let maximumCanonicalBytes = 256 * 1_024
    static let maximumLatitudeMicrodegrees: Int32 = 90_000_000
    static let maximumLongitudeMicrodegrees: Int32 = 180_000_000

    static func id(_ value: UUID) throws {
        guard value.uuidString != "00000000-0000-0000-0000-000000000000" else {
            throw EvidenceContextFailureV1.invalidIdentity
        }
    }
    static func token(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= maximumTokenBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
    static func digest(_ value: String) throws {
        guard value.utf8.count == 64, value == value.lowercased(),
              value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) }) else {
            throw EvidenceContextFailureV1.invalidDigest
        }
    }
    static func instant(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
    static func exactInt64(_ value: Double) throws -> Int64 {
        let rounded = value.rounded(.toNearestOrEven)
        // Double(Int64.max) rounds to 2^63, which is outside Int64. Keep the
        // upper comparison strict so conversion cannot trap at that boundary.
        guard rounded.isFinite, rounded >= Double(Int64.min),
              rounded < Double(Int64.max) else {
            throw EvidenceContextFailureV1.arithmeticOverflow
        }
        return Int64(rounded)
    }
    static func utcEpochSecond(_ value: Date) throws -> Int64 {
        try exactInt64(value.timeIntervalSince1970)
    }
    static func timeZone(_ identifier: String, matchesUTCOffset offset: Int,
                         at date: Date) throws -> TimeZone {
        try token(identifier); try instant(date)
        guard let timeZone = TimeZone(identifier: identifier),
              timeZone.secondsFromGMT(for: date) == offset else {
            throw EvidenceContextFailureV1.invalidValue
        }
        return timeZone
    }
    static func validateTimeZoneIfDeclared(in temporal: TemporalContextV1) throws {
        guard let identifier = temporal.ianaTimeZoneIdentifier else { return }
        try token(identifier)
        guard TimeZone(identifier: identifier) != nil else {
            throw EvidenceContextFailureV1.invalidValue
        }
        if let occurredAtUTC = temporal.occurredAtUTC,
           let utcOffsetSeconds = temporal.utcOffsetSeconds {
            _ = try timeZone(identifier, matchesUTCOffset: utcOffsetSeconds,
                             at: occurredAtUTC)
        }
    }
}

enum EvidenceLightingConditionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case daylight = "DAYLIGHT"
    case civilTwilight = "CIVIL_TWILIGHT"
    case night = "NIGHT"
    case coveredDayCondition = "COVERED_DAY_CONDITION"
    case coveredNightCondition = "COVERED_NIGHT_CONDITION"
    case unknown = "UNKNOWN"
}
typealias EvidenceContextConditionV1 = EvidenceLightingConditionV1

enum EvidenceContextDeclarationSourceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case userObserved = "USER_OBSERVED"
}

struct UserObservedEvidenceContextV1: Codable, Equatable, Hashable, Sendable {
    let condition: EvidenceLightingConditionV1
    let source: EvidenceContextDeclarationSourceV1
    let observationNoteCode: String?

    init(condition: EvidenceLightingConditionV1, observationNoteCode: String? = nil) throws {
        self.condition = condition; source = .userObserved
        self.observationNoteCode = observationNoteCode
        try validate()
    }
    func validate() throws {
        try observationNoteCode.map(EvidenceContextLimitsV1.token)
        guard source == .userObserved else { throw EvidenceContextFailureV1.invalidValue }
    }
}

struct SolarLocationV1: Codable, Equatable, Hashable, Sendable {
    let latitudeMicrodegrees: Int32
    let longitudeMicrodegrees: Int32
    let locationBasisSHA256: String

    init(latitudeMicrodegrees: Int32, longitudeMicrodegrees: Int32,
         locationBasisSHA256: String) throws {
        self.latitudeMicrodegrees = latitudeMicrodegrees
        self.longitudeMicrodegrees = longitudeMicrodegrees
        self.locationBasisSHA256 = locationBasisSHA256
        try validate()
    }
    func validate() throws {
        try EvidenceContextLimitsV1.digest(locationBasisSHA256)
        guard (-EvidenceContextLimitsV1.maximumLatitudeMicrodegrees...EvidenceContextLimitsV1.maximumLatitudeMicrodegrees).contains(latitudeMicrodegrees),
              (-EvidenceContextLimitsV1.maximumLongitudeMicrodegrees...EvidenceContextLimitsV1.maximumLongitudeMicrodegrees).contains(longitudeMicrodegrees) else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
}

enum SolarPolarDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case ordinary = "ORDINARY"
    case polarDay = "POLAR_DAY"
    case polarNight = "POLAR_NIGHT"
    case indeterminate = "INDETERMINATE"
}

enum DerivedSolarConditionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case daylight = "DAYLIGHT"
    case civilTwilight = "CIVIL_TWILIGHT"
    case night = "NIGHT"
    case unknown = "UNKNOWN"
}

struct SolarEventInstantV1: Codable, Equatable, Hashable, Sendable {
    let utcEpochSecond: Int64
    let localUTCOffsetSeconds: Int
    func validate() throws {
        let offset = Int64(localUTCOffsetSeconds)
        let maximum = Int64(TemporalContextV1.maximumAbsoluteUTCOffsetSeconds)
        guard offset >= -maximum, offset <= maximum else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
}

struct DerivedSolarContextV1: Codable, Equatable, Hashable, Sendable {
    static let currentCalculationVersion = 1
    let calculationVersion: Int
    let location: SolarLocationV1
    let ianaTimeZoneIdentifier: String
    let evaluatedUTCEpochSecond: Int64
    let utcOffsetSecondsAtEvaluation: Int
    let sunrise: SolarEventInstantV1?
    let sunset: SolarEventInstantV1?
    let civilTwilightDawn: SolarEventInstantV1?
    let civilTwilightDusk: SolarEventInstantV1?
    let polarDisposition: SolarPolarDispositionV1
    let derivedCondition: DerivedSolarConditionV1
    let calculationSHA256: String

    init(location: SolarLocationV1, ianaTimeZoneIdentifier: String,
         evaluatedUTCEpochSecond: Int64, utcOffsetSecondsAtEvaluation: Int,
         sunrise: SolarEventInstantV1?, sunset: SolarEventInstantV1?,
         civilTwilightDawn: SolarEventInstantV1?, civilTwilightDusk: SolarEventInstantV1?,
         polarDisposition: SolarPolarDispositionV1, derivedCondition: DerivedSolarConditionV1) throws {
        calculationVersion = Self.currentCalculationVersion; self.location = location
        self.ianaTimeZoneIdentifier = ianaTimeZoneIdentifier
        self.evaluatedUTCEpochSecond = evaluatedUTCEpochSecond
        self.utcOffsetSecondsAtEvaluation = utcOffsetSecondsAtEvaluation
        self.sunrise = sunrise; self.sunset = sunset
        self.civilTwilightDawn = civilTwilightDawn; self.civilTwilightDusk = civilTwilightDusk
        self.polarDisposition = polarDisposition; self.derivedCondition = derivedCondition
        calculationSHA256 = try EvidenceContextCanonicalCodecV1.sha256(Basis(
            calculationVersion: Self.currentCalculationVersion, location: location,
            ianaTimeZoneIdentifier: ianaTimeZoneIdentifier,
            evaluatedUTCEpochSecond: evaluatedUTCEpochSecond,
            utcOffsetSecondsAtEvaluation: utcOffsetSecondsAtEvaluation,
            sunrise: sunrise, sunset: sunset, civilTwilightDawn: civilTwilightDawn,
            civilTwilightDusk: civilTwilightDusk, polarDisposition: polarDisposition,
            derivedCondition: derivedCondition))
        try validate()
    }
    func validate() throws {
        try location.validate(); try EvidenceContextLimitsV1.token(ianaTimeZoneIdentifier)
        try sunrise?.validate(); try sunset?.validate()
        try civilTwilightDawn?.validate(); try civilTwilightDusk?.validate()
        guard let timeZone = TimeZone(identifier: ianaTimeZoneIdentifier) else {
            throw EvidenceContextFailureV1.invalidValue
        }
        let evaluationDate = Date(timeIntervalSince1970: Double(evaluatedUTCEpochSecond))
        let events = [sunrise, sunset, civilTwilightDawn, civilTwilightDusk].compactMap { $0 }
        let eventOffsetsMatchZone = events.allSatisfy { event in
            timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(event.utcEpochSecond)))
                == event.localUTCOffsetSeconds
        }
        let ordinaryCondition: DerivedSolarConditionV1? = {
            guard let sunrise, let sunset, let civilTwilightDawn, let civilTwilightDusk,
                  civilTwilightDawn.utcEpochSecond <= sunrise.utcEpochSecond,
                  sunrise.utcEpochSecond < sunset.utcEpochSecond,
                  sunset.utcEpochSecond <= civilTwilightDusk.utcEpochSecond else { return nil }
            if evaluatedUTCEpochSecond >= sunrise.utcEpochSecond,
               evaluatedUTCEpochSecond < sunset.utcEpochSecond { return .daylight }
            if evaluatedUTCEpochSecond >= civilTwilightDawn.utcEpochSecond,
               evaluatedUTCEpochSecond < civilTwilightDusk.utcEpochSecond { return .civilTwilight }
            return .night
        }()
        let offset = Int64(utcOffsetSecondsAtEvaluation)
        let maximumOffset = Int64(TemporalContextV1.maximumAbsoluteUTCOffsetSeconds)
        guard calculationVersion == Self.currentCalculationVersion,
              offset >= -maximumOffset, offset <= maximumOffset,
              timeZone.secondsFromGMT(for: evaluationDate) == utcOffsetSecondsAtEvaluation,
              eventOffsetsMatchZone,
              (polarDisposition == .ordinary) == (sunrise != nil && sunset != nil
                && civilTwilightDawn != nil && civilTwilightDusk != nil),
              polarDisposition == .ordinary || (sunrise == nil && sunset == nil
                && civilTwilightDawn == nil && civilTwilightDusk == nil),
              (polarDisposition == .polarDay ? derivedCondition == .daylight : true),
              (polarDisposition == .polarNight ? derivedCondition == .night : true),
              (polarDisposition == .indeterminate ? derivedCondition == .unknown : true),
              (polarDisposition == .ordinary ? ordinaryCondition == derivedCondition : true),
              calculationSHA256 == (try EvidenceContextCanonicalCodecV1.sha256(basis)) else {
            throw EvidenceContextFailureV1.invalidDigest
        }
    }
    private var basis: Basis { .init(calculationVersion: calculationVersion, location: location,
        ianaTimeZoneIdentifier: ianaTimeZoneIdentifier, evaluatedUTCEpochSecond: evaluatedUTCEpochSecond,
        utcOffsetSecondsAtEvaluation: utcOffsetSecondsAtEvaluation, sunrise: sunrise, sunset: sunset,
        civilTwilightDawn: civilTwilightDawn, civilTwilightDusk: civilTwilightDusk,
        polarDisposition: polarDisposition, derivedCondition: derivedCondition) }
    private struct Basis: Codable { let calculationVersion: Int; let location: SolarLocationV1; let ianaTimeZoneIdentifier: String; let evaluatedUTCEpochSecond: Int64; let utcOffsetSecondsAtEvaluation: Int; let sunrise: SolarEventInstantV1?; let sunset: SolarEventInstantV1?; let civilTwilightDawn: SolarEventInstantV1?; let civilTwilightDusk: SolarEventInstantV1?; let polarDisposition: SolarPolarDispositionV1; let derivedCondition: DerivedSolarConditionV1 }
}

enum ExpectedControlStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case expectedOperating = "EXPECTED_OPERATING"
    case expectedNotOperating = "EXPECTED_NOT_OPERATING"
    case noExpectation = "NO_EXPECTATION"
}

struct ControlExpectationV1: Codable, Equatable, Hashable, Sendable {
    /// A policy expectation only. No field represents observed operation,
    /// compliance, approval, or inferred equipment state.
    let controlGroupID: String
    let expectedState: ExpectedControlStateV1
    let policyID: String
    let policyVersion: Int
    let policySHA256: String

    init(controlGroupID: String, expectedState: ExpectedControlStateV1,
         policyID: String, policyVersion: Int, policySHA256: String) throws {
        self.controlGroupID = controlGroupID; self.expectedState = expectedState
        self.policyID = policyID; self.policyVersion = policyVersion; self.policySHA256 = policySHA256
        try validate()
    }
    func validate() throws {
        try EvidenceContextLimitsV1.token(controlGroupID); try EvidenceContextLimitsV1.token(policyID)
        try EvidenceContextLimitsV1.digest(policySHA256)
        guard policyVersion > 0 else { throw EvidenceContextFailureV1.invalidValue }
    }
}

struct EvidenceContextV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let contextID: UUID
    let workspaceID: WorkspaceID
    let evidenceID: String
    let evidenceSHA256: String
    let evidenceRevision: UInt64
    let assetID: UUID
    let assetRevision: UInt64
    let temporalContext: TemporalContextV1
    let userObserved: UserObservedEvidenceContextV1
    let derivedSolar: DerivedSolarContextV1?
    let controlExpectation: ControlExpectationV1?
    let predecessorContextSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let contextSHA256: String

    init(contextID: UUID, workspaceID: WorkspaceID, evidenceID: String,
         evidenceSHA256: String,
         evidenceRevision: UInt64, assetID: UUID, assetRevision: UInt64,
         temporalContext: TemporalContextV1, userObserved: UserObservedEvidenceContextV1,
         derivedSolar: DerivedSolarContextV1?, controlExpectation: ControlExpectationV1?,
         predecessor: Self?, revision: UInt64, mutationID: MutationIDV1,
         recordedBy: ActorSnapshotV1, recordedAt: Date) throws {
        schemaVersion = Self.currentSchemaVersion; self.contextID = contextID; self.workspaceID = workspaceID
        self.evidenceID = evidenceID; self.evidenceSHA256 = evidenceSHA256
        self.evidenceRevision = evidenceRevision
        self.assetID = assetID; self.assetRevision = assetRevision; self.temporalContext = temporalContext
        self.userObserved = userObserved; self.derivedSolar = derivedSolar
        self.controlExpectation = controlExpectation
        predecessorContextSHA256 = predecessor?.contextSHA256; self.revision = revision
        self.mutationID = mutationID; self.recordedBy = recordedBy; self.recordedAt = recordedAt
        contextSHA256 = try EvidenceContextCanonicalCodecV1.sha256(basisWithoutDigest)
        try validateIntrinsic(); if let predecessor { try validateSuccessor(of: predecessor) }
    }
    func validateIntrinsic() throws {
        try EvidenceContextLimitsV1.id(contextID); try EvidenceContextLimitsV1.id(assetID)
        try EvidenceContextLimitsV1.token(evidenceID); try EvidenceContextLimitsV1.digest(evidenceSHA256)
        try predecessorContextSHA256.map(EvidenceContextLimitsV1.digest)
        try temporalContext.validate()
        try EvidenceContextLimitsV1.validateTimeZoneIfDeclared(in: temporalContext)
        try userObserved.validate(); try derivedSolar?.validate()
        try controlExpectation?.validate(); try recordedBy.validate(); try EvidenceContextLimitsV1.instant(recordedAt)
        let solarMatchesTemporal: Bool = {
            guard let derivedSolar else { return true }
            guard let occurredAtUTC = temporalContext.occurredAtUTC,
                  let offset = temporalContext.utcOffsetSeconds,
                  let zone = temporalContext.ianaTimeZoneIdentifier else { return false }
            guard let epoch = try? EvidenceContextLimitsV1.utcEpochSecond(occurredAtUTC),
                  (try? EvidenceContextLimitsV1.timeZone(zone, matchesUTCOffset: offset,
                                                         at: occurredAtUTC)) != nil else { return false }
            return epoch == derivedSolar.evaluatedUTCEpochSecond
                && offset == derivedSolar.utcOffsetSecondsAtEvaluation
                && zone == derivedSolar.ianaTimeZoneIdentifier
        }()
        if let derivedSolar {
            let input = try SolarCalculationInputV1(location: derivedSolar.location,
                                                     temporalContext: temporalContext)
            guard try OfflineSolarCalculatorV1.calculate(input) == derivedSolar else {
                throw EvidenceContextFailureV1.referenceMismatch
            }
        }
        guard schemaVersion == Self.currentSchemaVersion, evidenceRevision > 0, assetRevision > 0, revision > 0,
              (revision == 1) == (predecessorContextSHA256 == nil),
              recordedBy.workspaceID == workspaceID, recordedBy.responsibility == .recordedBy,
              solarMatchesTemporal,
              temporalContext.recordedAtUTC <= recordedAt,
              contextSHA256 == (try EvidenceContextCanonicalCodecV1.sha256(basisWithoutDigest)) else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateIntrinsic(); try validateIntrinsic()
        guard predecessor.revision < UInt64.max, workspaceID == predecessor.workspaceID,
              evidenceID == predecessor.evidenceID, evidenceRevision == predecessor.evidenceRevision,
              evidenceSHA256 == predecessor.evidenceSHA256,
              assetID == predecessor.assetID, assetRevision == predecessor.assetRevision,
              contextID != predecessor.contextID, predecessorContextSHA256 == predecessor.contextSHA256,
              revision == predecessor.revision + 1, mutationID != predecessor.mutationID else {
            throw EvidenceContextFailureV1.predecessorMismatch
        }
    }
    func rebound(to workspaceID: WorkspaceID, predecessor: Self?,
                 recordedBy: ActorSnapshotV1) throws -> Self {
        guard recordedBy.workspaceID == workspaceID else { throw EvidenceContextFailureV1.wrongWorkspace }
        if let predecessor, predecessor.revision == UInt64.max {
            throw EvidenceContextFailureV1.arithmeticOverflow
        }
        return try .init(contextID: contextID, workspaceID: workspaceID,
            evidenceID: evidenceID, evidenceSHA256: evidenceSHA256,
            evidenceRevision: evidenceRevision, assetID: assetID,
            assetRevision: assetRevision, temporalContext: temporalContext,
            userObserved: userObserved, derivedSolar: derivedSolar,
            controlExpectation: controlExpectation, predecessor: predecessor,
            revision: predecessor.map { $0.revision + 1 } ?? 1,
            mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt)
    }
    private var basisWithoutDigest: Basis { .init(schemaVersion: schemaVersion, contextID: contextID,
        workspaceID: workspaceID, evidenceID: evidenceID, evidenceSHA256: evidenceSHA256,
        evidenceRevision: evidenceRevision,
        assetID: assetID, assetRevision: assetRevision, temporalContext: temporalContext,
        userObserved: userObserved, derivedSolar: derivedSolar, controlExpectation: controlExpectation,
        predecessorContextSHA256: predecessorContextSHA256, revision: revision, mutationID: mutationID,
        recordedBy: recordedBy, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let contextID: UUID; let workspaceID: WorkspaceID; let evidenceID: String; let evidenceSHA256: String; let evidenceRevision: UInt64; let assetID: UUID; let assetRevision: UInt64; let temporalContext: TemporalContextV1; let userObserved: UserObservedEvidenceContextV1; let derivedSolar: DerivedSolarContextV1?; let controlExpectation: ControlExpectationV1?; let predecessorContextSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let recordedBy: ActorSnapshotV1; let recordedAt: Date }
}

enum PairedObservationPurposeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case conditionComparison = "CONDITION_COMPARISON"
    case controlStateComparison = "CONTROL_STATE_COMPARISON"
    case beforeAfterComparison = "BEFORE_AFTER_COMPARISON"
}

struct PairedObservationReferenceV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let evidenceID: String; let evidenceSHA256: String; let evidenceRevision: UInt64
    let assetID: UUID; let assetRevision: UInt64; let controlGroupID: String
    let purpose: PairedObservationPurposeV1; let purposeRevision: UInt64
    let planReferenceSHA256: String?
    let viewpointReferenceSHA256: String; let temporalBucketID: String
    let surfaceWeatherBasisSHA256: String; let measurementMethodID: String
    func validate() throws {
        try EvidenceContextLimitsV1.token(evidenceID); try EvidenceContextLimitsV1.digest(evidenceSHA256)
        try EvidenceContextLimitsV1.id(assetID); try EvidenceContextLimitsV1.token(controlGroupID)
        try planReferenceSHA256.map(EvidenceContextLimitsV1.digest)
        try EvidenceContextLimitsV1.digest(viewpointReferenceSHA256)
        try EvidenceContextLimitsV1.token(temporalBucketID)
        try EvidenceContextLimitsV1.digest(surfaceWeatherBasisSHA256)
        try EvidenceContextLimitsV1.token(measurementMethodID)
        guard evidenceRevision > 0, assetRevision > 0, purposeRevision > 0 else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
    func rebound(to workspaceID: WorkspaceID) -> Self {
        .init(workspaceID: workspaceID, evidenceID: evidenceID,
              evidenceSHA256: evidenceSHA256, evidenceRevision: evidenceRevision,
              assetID: assetID, assetRevision: assetRevision,
              controlGroupID: controlGroupID, purpose: purpose,
              purposeRevision: purposeRevision, planReferenceSHA256: planReferenceSHA256,
              viewpointReferenceSHA256: viewpointReferenceSHA256,
              temporalBucketID: temporalBucketID,
              surfaceWeatherBasisSHA256: surfaceWeatherBasisSHA256,
              measurementMethodID: measurementMethodID)
    }
}

enum PairedObservationMismatchReasonV1: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case planMismatch = "PLAN_MISMATCH"
    case viewpointMismatch = "VIEWPOINT_MISMATCH"
    case timeMismatch = "TIME_MISMATCH"
    case controlMismatch = "CONTROL_MISMATCH"
    case assetRevisionMismatch = "ASSET_REVISION_MISMATCH"
    case surfaceWeatherMismatch = "SURFACE_WEATHER_MISMATCH"
    case measurementMethodMismatch = "MEASUREMENT_METHOD_MISMATCH"
    case purposeMismatch = "PURPOSE_MISMATCH"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct PairedObservationLinkV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int; let linkID: UUID; let workspaceID: WorkspaceID
    let first: PairedObservationReferenceV1; let second: PairedObservationReferenceV1
    let mismatchReasons: [PairedObservationMismatchReasonV1]
    let predecessorLinkSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1; let recordedAt: Date; let linkSHA256: String

    init(linkID: UUID, workspaceID: WorkspaceID, first: PairedObservationReferenceV1,
         second: PairedObservationReferenceV1, predecessor: Self?, revision: UInt64,
         mutationID: MutationIDV1, recordedBy: ActorSnapshotV1, recordedAt: Date) throws {
        schemaVersion = Self.currentSchemaVersion; self.linkID = linkID; self.workspaceID = workspaceID
        if Self.stableKey(first) < Self.stableKey(second) {
            self.first = first; self.second = second
        } else {
            self.first = second; self.second = first
        }
        mismatchReasons = Self.mismatches(self.first, self.second)
        predecessorLinkSHA256 = predecessor?.linkSHA256; self.revision = revision
        self.mutationID = mutationID; self.recordedBy = recordedBy; self.recordedAt = recordedAt
        linkSHA256 = try EvidenceContextCanonicalCodecV1.sha256(basisWithoutDigest)
        try validateIntrinsic(); if let predecessor { try validateSuccessor(of: predecessor) }
    }
    static func mismatches(_ lhs: PairedObservationReferenceV1,
                           _ rhs: PairedObservationReferenceV1) -> [PairedObservationMismatchReasonV1] {
        var values = Set<PairedObservationMismatchReasonV1>()
        if lhs.purpose != rhs.purpose || lhs.purposeRevision != rhs.purposeRevision {
            values.insert(.purposeMismatch)
        }
        if lhs.planReferenceSHA256 != rhs.planReferenceSHA256 { values.insert(.planMismatch) }
        if lhs.viewpointReferenceSHA256 != rhs.viewpointReferenceSHA256 { values.insert(.viewpointMismatch) }
        if lhs.temporalBucketID != rhs.temporalBucketID { values.insert(.timeMismatch) }
        if lhs.assetID != rhs.assetID || lhs.controlGroupID != rhs.controlGroupID { values.insert(.controlMismatch) }
        if lhs.assetRevision != rhs.assetRevision { values.insert(.assetRevisionMismatch) }
        if lhs.surfaceWeatherBasisSHA256 != rhs.surfaceWeatherBasisSHA256 { values.insert(.surfaceWeatherMismatch) }
        if lhs.measurementMethodID != rhs.measurementMethodID { values.insert(.measurementMethodMismatch) }
        return values.sorted()
    }
    func validateIntrinsic() throws {
        try EvidenceContextLimitsV1.id(linkID); try first.validate(); try second.validate()
        try predecessorLinkSHA256.map(EvidenceContextLimitsV1.digest)
        try recordedBy.validate(); try EvidenceContextLimitsV1.instant(recordedAt)
        guard schemaVersion == Self.currentSchemaVersion, first.evidenceID != second.evidenceID,
              Self.stableKey(first) < Self.stableKey(second),
              first.workspaceID == workspaceID, second.workspaceID == workspaceID,
              first.assetID == second.assetID, mismatchReasons == mismatchReasons.sorted(),
              Set(mismatchReasons).count == mismatchReasons.count,
              mismatchReasons.count <= EvidenceContextLimitsV1.maximumMismatchReasons,
              mismatchReasons == Self.mismatches(first, second), revision > 0,
              (revision == 1) == (predecessorLinkSHA256 == nil),
              recordedBy.workspaceID == workspaceID, recordedBy.responsibility == .recordedBy,
              linkSHA256 == (try EvidenceContextCanonicalCodecV1.sha256(basisWithoutDigest)) else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
    private static func stableKey(_ value: PairedObservationReferenceV1) -> String {
        "\(value.workspaceID.rawValue.uuidString.lowercased())\u{0}\(value.evidenceID)\u{0}\(value.evidenceRevision)\u{0}\(value.evidenceSHA256)"
    }
    func validateCompatiblePair() throws {
        try validateIntrinsic()
        guard mismatchReasons.isEmpty else { throw EvidenceContextFailureV1.referenceMismatch }
    }
    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateIntrinsic(); try validateIntrinsic()
        guard predecessor.revision < UInt64.max, workspaceID == predecessor.workspaceID,
              linkID != predecessor.linkID, first == predecessor.first, second == predecessor.second,
              predecessorLinkSHA256 == predecessor.linkSHA256,
              revision == predecessor.revision + 1, mutationID != predecessor.mutationID else {
            throw EvidenceContextFailureV1.predecessorMismatch
        }
    }
    func rebound(to workspaceID: WorkspaceID, predecessor: Self?,
                 recordedBy: ActorSnapshotV1) throws -> Self {
        guard recordedBy.workspaceID == workspaceID else { throw EvidenceContextFailureV1.wrongWorkspace }
        if let predecessor, predecessor.revision == UInt64.max {
            throw EvidenceContextFailureV1.arithmeticOverflow
        }
        return try .init(linkID: linkID, workspaceID: workspaceID,
            first: first.rebound(to: workspaceID), second: second.rebound(to: workspaceID),
            predecessor: predecessor, revision: predecessor.map { $0.revision + 1 } ?? 1,
            mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt)
    }
    private var basisWithoutDigest: Basis { .init(schemaVersion: schemaVersion, linkID: linkID,
        workspaceID: workspaceID, first: first, second: second, mismatchReasons: mismatchReasons,
        predecessorLinkSHA256: predecessorLinkSHA256, revision: revision,
        mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let linkID: UUID; let workspaceID: WorkspaceID; let first: PairedObservationReferenceV1; let second: PairedObservationReferenceV1; let mismatchReasons: [PairedObservationMismatchReasonV1]; let predecessorLinkSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let recordedBy: ActorSnapshotV1; let recordedAt: Date }
}

enum EvidenceContextCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= EvidenceContextLimitsV1.maximumCanonicalBytes else {
            throw EvidenceContextFailureV1.invalidValue
        }
        return data
    }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= EvidenceContextLimitsV1.maximumCanonicalBytes else {
            throw EvidenceContextFailureV1.invalidValue
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        if let validating = value as? any EvidenceContextCanonicalValidatingV1 {
            try validating.validateForCanonicalCoding()
        }
        guard try encode(value) == data else { throw EvidenceContextFailureV1.nonCanonicalEncoding }
        return value
    }
    static func sha256<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try encode(value)).map { String(format: "%02x", $0) }.joined()
    }
}

private protocol EvidenceContextCanonicalValidatingV1 {
    func validateForCanonicalCoding() throws
}
extension EvidenceContextV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validateIntrinsic() }
}
extension UserObservedEvidenceContextV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validate() }
}
extension SolarLocationV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validate() }
}
extension SolarEventInstantV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validate() }
}
extension PairedObservationLinkV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validateIntrinsic() }
}
extension DerivedSolarContextV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validate() }
}
extension ControlExpectationV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validate() }
}
extension PairedObservationReferenceV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validate() }
}

struct SolarCalculationInputV1: Codable, Equatable, Sendable {
    let location: SolarLocationV1; let temporalContext: TemporalContextV1
    init(location: SolarLocationV1, temporalContext: TemporalContextV1) throws {
        self.location = location; self.temporalContext = temporalContext
        try validate()
    }
    func validate() throws {
        try location.validate(); try temporalContext.validate()
        guard let occurredAtUTC = temporalContext.occurredAtUTC,
              let utcOffsetSeconds = temporalContext.utcOffsetSeconds,
              let ianaTimeZoneIdentifier = temporalContext.ianaTimeZoneIdentifier,
              temporalContext.localTimeDisposition == .unambiguous else {
            throw EvidenceContextFailureV1.invalidValue
        }
        _ = try EvidenceContextLimitsV1.utcEpochSecond(occurredAtUTC)
        _ = try EvidenceContextLimitsV1.timeZone(ianaTimeZoneIdentifier,
                                                 matchesUTCOffset: utcOffsetSeconds,
                                                 at: occurredAtUTC)
    }
}

extension SolarCalculationInputV1: EvidenceContextCanonicalValidatingV1 {
    fileprivate func validateForCanonicalCoding() throws { try validate() }
}

enum OfflineSolarCalculatorV1 {
    /// Provider-free NOAA-style calculation. Inputs are fixed-point; emitted
    /// instants are integral UTC seconds rounded nearest-ties-to-even.
    static func calculate(_ input: SolarCalculationInputV1) throws -> DerivedSolarContextV1 {
        try input.location.validate(); try input.temporalContext.validate()
        guard let occurred = input.temporalContext.occurredAtUTC,
              let offset = input.temporalContext.utcOffsetSeconds,
              let zone = input.temporalContext.ianaTimeZoneIdentifier else {
            throw EvidenceContextFailureV1.invalidValue
        }
        let timeZone = try EvidenceContextLimitsV1.timeZone(zone, matchesUTCOffset: offset,
                                                           at: occurred)
        let epoch = try EvidenceContextLimitsV1.utcEpochSecond(occurred)
        let day = floor(Double(epoch) / 86_400.0)
        let latitude = Double(input.location.latitudeMicrodegrees) / 1_000_000.0
        let longitude = Double(input.location.longitudeMicrodegrees) / 1_000_000.0
        func event(zenith: Double, rising: Bool) throws -> (Int64?, SolarPolarDispositionV1?) {
            let n = day + 2_440_587.5 - 2_451_545.0 + 0.0008
            let jStar = n - longitude / 360.0
            let meanAnomaly = (357.5291 + 0.98560028 * jStar) * .pi / 180.0
            let center = 1.9148 * sin(meanAnomaly) + 0.0200 * sin(2 * meanAnomaly) + 0.0003 * sin(3 * meanAnomaly)
            let lambda = (meanAnomaly * 180.0 / .pi + center + 180.0 + 102.9372) * .pi / 180.0
            let transit = 2_451_545.0 + jStar + 0.0053 * sin(meanAnomaly) - 0.0069 * sin(2 * lambda)
            let declination = asin(sin(lambda) * sin(23.44 * .pi / 180.0))
            let lat = latitude * .pi / 180.0
            let cosine = (cos(zenith * .pi / 180.0) - sin(lat) * sin(declination))
                / (cos(lat) * cos(declination))
            if cosine > 1 { return (nil, .polarNight) }
            if cosine < -1 { return (nil, .polarDay) }
            let hour = acos(cosine) / (2 * .pi)
            let julian = rising ? transit - hour : transit + hour
            let seconds = (julian - 2_440_587.5) * 86_400.0
            return (try EvidenceContextLimitsV1.exactInt64(seconds), nil)
        }
        let rise = try event(zenith: 90.833, rising: true)
        let set = try event(zenith: 90.833, rising: false)
        let dawn = try event(zenith: 96.0, rising: true)
        let dusk = try event(zenith: 96.0, rising: false)
        let polarFlags = [rise.1, set.1, dawn.1, dusk.1].compactMap { $0 }
        let polar: SolarPolarDispositionV1
        if polarFlags.isEmpty { polar = .ordinary }
        else if Set(polarFlags).count == 1 { polar = polarFlags[0] }
        else { polar = .indeterminate }
        func instant(_ value: Int64?) -> SolarEventInstantV1? {
            value.map {
                let date = Date(timeIntervalSince1970: Double($0))
                return .init(utcEpochSecond: $0,
                             localUTCOffsetSeconds: timeZone.secondsFromGMT(for: date))
            }
        }
        let derived: DerivedSolarConditionV1
        if polar == .polarDay { derived = .daylight }
        else if polar == .polarNight { derived = .night }
        else if polar != .ordinary { derived = .unknown }
        else if let sunrise = rise.0, let sunset = set.0, epoch >= sunrise && epoch < sunset { derived = .daylight }
        else if let dawn = dawn.0, let dusk = dusk.0, epoch >= dawn && epoch < dusk { derived = .civilTwilight }
        else { derived = .night }
        let emittedRise = polar == .ordinary ? rise.0 : nil
        let emittedSet = polar == .ordinary ? set.0 : nil
        let emittedDawn = polar == .ordinary ? dawn.0 : nil
        let emittedDusk = polar == .ordinary ? dusk.0 : nil
        return try .init(location: input.location, ianaTimeZoneIdentifier: zone,
            evaluatedUTCEpochSecond: epoch, utcOffsetSecondsAtEvaluation: offset,
            sunrise: instant(emittedRise), sunset: instant(emittedSet),
            civilTwilightDawn: instant(emittedDawn), civilTwilightDusk: instant(emittedDusk),
            polarDisposition: polar, derivedCondition: derived)
    }
}
