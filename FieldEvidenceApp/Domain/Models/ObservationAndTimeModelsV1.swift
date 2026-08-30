import Foundation
enum EvidenceContextObservationTimeBoundaryV1{static let observedAndCalculatedTimesAreCanonicalReceiptInputs=true;static let derivedSolarPreviewIsNotPersistedSeparately=true}
enum PlacementPoseObservationTimeBoundaryV1{static let poseTimesUseCanonicalMilliseconds=true;static let deviceHeadingProposalsAreNotDurableUntilAccepted=true}

enum ObservationScheduleBoundaryV1 { static let scheduleTimeBasisIsFrozen = true }

enum C51ObservationTimeScheduleBoundaryV1 {
    static let occurrenceBasisReusesFrozenScheduleTimeBasis = true
    static let deviceCurrentTimeZoneIsNotReinterpreted = true
    static let scheduleClosureMetadataIsDerivedOnly = true
}
import SwiftData

enum PlanObservationPlacementBindingV1 { static let observationSubjectKind = PlanPlacementSubjectKindV1.observation; static let placementOwnsNoObservationBytes = true }

/// V5 companion entity. `WorkflowRecord` remains byte-for-byte the frozen V4
/// model; this scalar key is intentionally not a SwiftData relationship.
@Model
final class ObservationAndTimeRow {
    static let currentSchemaVersion = 1

    @Attribute(.unique) var recordID: UUID
    var schemaVersion: Int
    var observationBasisV1Data: Data
    var temporalContextV1Data: Data

    init(
        recordID: UUID,
        observationBasisV1Data: Data,
        temporalContextV1Data: Data,
        schemaVersion: Int = currentSchemaVersion
    ) throws {
        self.recordID = recordID
        self.schemaVersion = schemaVersion
        self.observationBasisV1Data = observationBasisV1Data
        self.temporalContextV1Data = temporalContextV1Data
        try validate()
    }

    convenience init(
        recordID: UUID,
        observationBasis: ObservationBasisV1,
        temporalContext: TemporalContextV1
    ) throws {
        try self.init(
            recordID: recordID,
            observationBasisV1Data: ObservationAndTimeCodecV1.encode(observationBasis),
            temporalContextV1Data: ObservationAndTimeCodecV1.encode(temporalContext)
        )
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ObservationAndTimeValidationFailureV1.unsupportedSchemaVersion
        }
        _ = try observationBasisV1()
        _ = try temporalContextV1()
    }

    func observationBasisV1() throws -> ObservationBasisV1 {
        try ObservationAndTimeCodecV1.decodeObservationBasis(observationBasisV1Data)
    }

    func temporalContextV1() throws -> TemporalContextV1 {
        try ObservationAndTimeCodecV1.decodeTemporalContext(temporalContextV1Data)
    }
}

enum C33TemporalEvidenceTimeModelBoundaryV1 { static let anchorTimeBase="CLIP_RELATIVE_MONOTONIC_MILLISECONDS";static let wallClockDefinesAnchorOrdering=false;static let canonicalMutationKind:WorkspaceCommandKindV1 = .applyTemporalEvidence }

enum ObservationAndTimeRowFailureV1: Error, Equatable, Sendable {
    case missingRow(UUID)
    case duplicateRow(UUID)
    case orphanRow(UUID)
    case rowLimitExceeded
    case invalidRow(UUID)
}

enum ObservationAndTimeRowStoreV1 {
    static let maximumRows = 100_000

    static func requireRow(
        recordID: UUID,
        in context: ModelContext
    ) throws -> ObservationAndTimeRow {
        var descriptor = FetchDescriptor<ObservationAndTimeRow>(
            predicate: #Predicate { $0.recordID == recordID }
        )
        descriptor.fetchLimit = 2
        let rows = try context.fetch(descriptor)
        guard rows.count <= 1 else {
            throw ObservationAndTimeRowFailureV1.duplicateRow(recordID)
        }
        guard let row = rows.first else {
            throw ObservationAndTimeRowFailureV1.missingRow(recordID)
        }
        do { try row.validate() } catch {
            throw ObservationAndTimeRowFailureV1.invalidRow(recordID)
        }
        return row
    }

    static func validatedIndex(
        in context: ModelContext,
        requireExactRecordSet: Bool = true
    ) throws -> [UUID: ObservationAndTimeRow] {
        var descriptor = FetchDescriptor<ObservationAndTimeRow>()
        descriptor.fetchLimit = maximumRows + 1
        let rows = try context.fetch(descriptor)
        guard rows.count <= maximumRows else {
            throw ObservationAndTimeRowFailureV1.rowLimitExceeded
        }
        var result: [UUID: ObservationAndTimeRow] = [:]
        result.reserveCapacity(rows.count)
        for row in rows {
            guard result[row.recordID] == nil else {
                throw ObservationAndTimeRowFailureV1.duplicateRow(row.recordID)
            }
            do { try row.validate() } catch {
                throw ObservationAndTimeRowFailureV1.invalidRow(row.recordID)
            }
            result[row.recordID] = row
        }
        if requireExactRecordSet {
            var recordsDescriptor = FetchDescriptor<WorkflowRecord>()
            recordsDescriptor.fetchLimit = maximumRows + 1
            let recordIDs = try context.fetch(recordsDescriptor).map(\.id)
            guard recordIDs.count <= maximumRows else {
                throw ObservationAndTimeRowFailureV1.rowLimitExceeded
            }
            let expected = Set(recordIDs)
            for recordID in expected where result[recordID] == nil {
                throw ObservationAndTimeRowFailureV1.missingRow(recordID)
            }
            for recordID in result.keys where !expected.contains(recordID) {
                throw ObservationAndTimeRowFailureV1.orphanRow(recordID)
            }
        }
        return result
    }
}

enum ObservationAndTimeValidationFailureV1: Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case invalidObservationBasis
    case invalidTemporalContext
    case encodedValueTooLarge
    case malformedEncoding
}

enum ObservationBasisKindV1: String, CaseIterable, Codable, Equatable, Sendable {
    case directlyObserved = "DIRECTLY_OBSERVED"
    case reported = "REPORTED"
    case inferred = "INFERRED"
    case notObserved = "NOT_OBSERVED"
    case unverifiable = "UNVERIFIABLE"
    case unknown = "UNKNOWN"
}

struct ObservationMethodV1: Codable, Equatable, Sendable {
    static let unknownKey = "unknown"

    let key: String

    init(key: String) throws {
        self.key = key
        try validate()
    }

    func validate() throws {
        guard ObservationAndTimeValidationV1.isBoundedToken(key, maximumBytes: 128) else {
            throw ObservationAndTimeValidationFailureV1.invalidObservationBasis
        }
    }
}

enum ObservationSourceKindV1: String, CaseIterable, Codable, Equatable, Sendable {
    case observer = "OBSERVER"
    case reportedParty = "REPORTED_PARTY"
    case record = "RECORD"
    case unknown = "UNKNOWN"
}

/// A bounded reference, never a verified identity claim. Unknown is an
/// explicit value and is not replaced with the current device or user.
struct ObservationSourceReferenceV1: Codable, Equatable, Sendable {
    let kind: ObservationSourceKindV1
    let reference: String?

    init(kind: ObservationSourceKindV1, reference: String? = nil) throws {
        self.kind = kind
        self.reference = reference
        try validate()
    }

    func validate() throws {
        switch kind {
        case .observer, .unknown:
            guard reference == nil else {
                throw ObservationAndTimeValidationFailureV1.invalidObservationBasis
            }
        case .reportedParty, .record:
            guard let reference,
                  ObservationAndTimeValidationV1.isBoundedText(
                    reference,
                    maximumBytes: 512
                  ) else {
                throw ObservationAndTimeValidationFailureV1.invalidObservationBasis
            }
        }
    }
}

/// Evidence basis is deliberately independent from the workflow outcome.
/// It contains no confidence score and cannot imply compliant/noncompliant.
struct ObservationBasisV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumLimitationCount = 16

    let version: Int
    let kind: ObservationBasisKindV1
    let method: ObservationMethodV1
    let source: ObservationSourceReferenceV1
    let limitations: [String]

    init(
        kind: ObservationBasisKindV1,
        method: ObservationMethodV1,
        source: ObservationSourceReferenceV1,
        limitations: [String] = []
    ) throws {
        version = Self.schemaVersion
        self.kind = kind
        self.method = method
        self.source = source
        self.limitations = limitations
        try validate()
    }

    func validate() throws {
        guard version == Self.schemaVersion else {
            throw ObservationAndTimeValidationFailureV1.unsupportedSchemaVersion
        }
        guard limitations.count <= Self.maximumLimitationCount,
              Set(limitations).count == limitations.count,
              limitations.allSatisfy({
                ObservationAndTimeValidationV1.isBoundedText(
                    $0,
                    maximumBytes: 2_048
                )
              }) else {
            throw ObservationAndTimeValidationFailureV1.invalidObservationBasis
        }
        try method.validate()
        try source.validate()

        switch kind {
        case .directlyObserved:
            guard source.kind == .observer else {
                throw ObservationAndTimeValidationFailureV1.invalidObservationBasis
            }
        case .reported:
            guard source.kind == .reportedParty || source.kind == .unknown else {
                throw ObservationAndTimeValidationFailureV1.invalidObservationBasis
            }
        case .inferred:
            guard source.kind == .record || source.kind == .unknown else {
                throw ObservationAndTimeValidationFailureV1.invalidObservationBasis
            }
        case .notObserved, .unverifiable, .unknown:
            break
        }
    }
}

enum LocalTimeDispositionV1: String, CaseIterable, Codable, Equatable, Sendable {
    case unambiguous = "UNAMBIGUOUS"
    case ambiguousFold = "AMBIGUOUS_FOLD"
    case nonexistentGap = "NONEXISTENT_GAP"
    case unknown = "UNKNOWN"
}

/// Durable display/evidence time. It is never a causal-order token; accepted
/// mutation order and revisions remain the only ordering authority.
struct TemporalContextV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumAbsoluteUTCOffsetSeconds = 18 * 60 * 60
    static let maximumTimeZoneIdentifierBytes = 255

    let version: Int
    let occurredAtUTC: Date?
    let recordedAtUTC: Date
    let localDate: String?
    let localTime: String?
    let utcOffsetSeconds: Int?
    let ianaTimeZoneIdentifier: String?
    let localTimeDisposition: LocalTimeDispositionV1

    init(
        occurredAtUTC: Date?,
        recordedAtUTC: Date,
        localDate: String?,
        localTime: String?,
        utcOffsetSeconds: Int?,
        ianaTimeZoneIdentifier: String?,
        localTimeDisposition: LocalTimeDispositionV1
    ) throws {
        version = Self.schemaVersion
        self.occurredAtUTC = occurredAtUTC
        self.recordedAtUTC = recordedAtUTC
        self.localDate = localDate
        self.localTime = localTime
        self.utcOffsetSeconds = utcOffsetSeconds
        self.ianaTimeZoneIdentifier = ianaTimeZoneIdentifier
        self.localTimeDisposition = localTimeDisposition
        try validate()
    }

    func validate() throws {
        let offsetRange = -Self.maximumAbsoluteUTCOffsetSeconds...
            Self.maximumAbsoluteUTCOffsetSeconds
        guard version == Self.schemaVersion else {
            throw ObservationAndTimeValidationFailureV1.unsupportedSchemaVersion
        }
        guard Self.isFinite(recordedAtUTC),
              occurredAtUTC.map(Self.isFinite) ?? true,
              (localDate == nil) == (localTime == nil),
              localDate.map(ObservationAndTimeValidationV1.isISODate) ?? true,
              localTime.map(ObservationAndTimeValidationV1.isISOTime) ?? true,
              utcOffsetSeconds.map(offsetRange.contains) ?? true,
              ianaTimeZoneIdentifier.map({
                ObservationAndTimeValidationV1.isBoundedTimeZoneIdentifier(
                    $0,
                    maximumBytes: Self.maximumTimeZoneIdentifierBytes
                )
              }) ?? true else {
            throw ObservationAndTimeValidationFailureV1.invalidTemporalContext
        }

        switch localTimeDisposition {
        case .unambiguous:
            guard occurredAtUTC != nil, localDate != nil, utcOffsetSeconds != nil else {
                throw ObservationAndTimeValidationFailureV1.invalidTemporalContext
            }
        case .ambiguousFold:
            guard localDate != nil, ianaTimeZoneIdentifier != nil else {
                throw ObservationAndTimeValidationFailureV1.invalidTemporalContext
            }
        case .nonexistentGap:
            guard occurredAtUTC == nil, localDate != nil,
                  ianaTimeZoneIdentifier != nil else {
                throw ObservationAndTimeValidationFailureV1.invalidTemporalContext
            }
        case .unknown:
            break
        }
    }

    private static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }
}

enum ObservationAndTimeSchemaV1 {
    static let version = 1
    static let maximumEncodedValueBytes = 32 * 1_024
}

enum ObservationAndTimeCodecV1 {
    static func encode(_ value: ObservationBasisV1) throws -> Data {
        try value.validate()
        return try canonicalEncoder().encode(value).boundedObservationAndTimeData()
    }

    static func decodeObservationBasis(_ data: Data) throws -> ObservationBasisV1 {
        try requireBounded(data)
        do {
            let value = try canonicalDecoder().decode(ObservationBasisV1.self, from: data)
            try value.validate()
            guard try encode(value) == data else {
                throw ObservationAndTimeValidationFailureV1.malformedEncoding
            }
            return value
        } catch let error as ObservationAndTimeValidationFailureV1 {
            throw error
        } catch {
            throw ObservationAndTimeValidationFailureV1.malformedEncoding
        }
    }

    static func encode(_ value: TemporalContextV1) throws -> Data {
        try value.validate()
        return try canonicalEncoder().encode(value).boundedObservationAndTimeData()
    }

    static func decodeTemporalContext(_ data: Data) throws -> TemporalContextV1 {
        try requireBounded(data)
        do {
            let value = try canonicalDecoder().decode(TemporalContextV1.self, from: data)
            try value.validate()
            guard try encode(value) == data else {
                throw ObservationAndTimeValidationFailureV1.malformedEncoding
            }
            return value
        } catch let error as ObservationAndTimeValidationFailureV1 {
            throw error
        } catch {
            throw ObservationAndTimeValidationFailureV1.malformedEncoding
        }
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func canonicalDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func requireBounded(_ data: Data) throws {
        guard !data.isEmpty,
              data.count <= ObservationAndTimeSchemaV1.maximumEncodedValueBytes else {
            throw ObservationAndTimeValidationFailureV1.encodedValueTooLarge
        }
    }
}

// MARK: - C19 measurement capture bridge

extension ObservationBasisV1 {
    /// Measurement capture may retain a reported/not-observed basis, but an
    /// instrument-backed capture must be directly observed. Inferred basis is
    /// never promoted into a C19 measurement capture.
    func c19ValidateMeasurementCapture(
        sourceMode: MeasurementCaptureSourceModeV1
    ) throws {
        try validate()
        switch sourceMode {
        case .manualEntry:
            guard kind != .inferred else {
                throw MeasurementIntegrityFailureV1.unsupportedSource
            }
        case .localObservation:
            guard kind == .directlyObserved else {
                throw MeasurementIntegrityFailureV1.unsupportedSource
            }
        }
    }
}

extension TemporalContextV1 {
    /// A temporal context is a recorded fact, not a causal-order token. The
    /// only C19 ordering check is that recording cannot precede capture.
    func c19ValidateMeasurementCaptureTime(_ capturedAt: Date) throws {
        try validate()
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite,
              recordedAtUTC >= capturedAt else {
            throw MeasurementIntegrityFailureV1.invalidValue
        }
    }
}

// MARK: - C20 reviewed-derivative observation boundary

extension ObservationBasisV1 {
    /// Observation basis remains descriptive evidence. This seam validates a
    /// separately reviewed C20 derivative without turning the observation into
    /// an identity, safety, or compliance claim.
    func c20ValidateReviewedDerivative(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        try validate()
        return try C20PrivacyProjectionBridgeV1.requireAllowed(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }
}

extension TemporalContextV1 {
    /// A review/render timestamp is a recorded fact and cannot precede the
    /// observation record that supplies its source context.
    func c20ValidatePrivacyReviewTime(_ reviewedAt: Date) throws {
        try validate()
        guard reviewedAt.timeIntervalSinceReferenceDate.isFinite,
              reviewedAt >= recordedAtUTC else {
            throw PrivacyTransformFailureV1.invalidValue
        }
    }
}

enum ObservationAndTimeLegacyMigrationV1 {
    /// Existing CNV bytes stay in their legacy columns. This adds only the
    /// defensible basis kind and never manufactures direct observation.
    static func observationBasis(
        couldNotVerifyKey: String?,
        displaySnapshot: String?,
        registryVersion: String?
    ) throws -> ObservationBasisV1? {
        let values = [couldNotVerifyKey, displaySnapshot, registryVersion]
        let hasLegacyCouldNotVerify = values.contains(where: { $0 != nil })
        let complete = values.allSatisfy { value in
            value.map({ ObservationAndTimeValidationV1.isBoundedText($0, maximumBytes: 2_048) }) ?? false
        }
        return try ObservationBasisV1(
            kind: hasLegacyCouldNotVerify && complete ? .unverifiable : .unknown,
            // The legacy CNV reason is retained in its original columns; it
            // is not evidence of how an observation was performed.
            method: ObservationMethodV1(key: ObservationMethodV1.unknownKey),
            source: ObservationSourceReferenceV1(kind: .unknown),
            limitations: [
                hasLegacyCouldNotVerify
                    ? "legacy_information_retained_separately"
                    : "legacy_basis_not_recorded"
            ]
        )
    }

    static func temporalContext(
        observedAtUTC: Date?,
        recordedAtUTC: Date,
        timeZoneID: String?,
        utcOffsetMinutes: Int?,
        localDate: String?,
        localTime: String?
    ) throws -> TemporalContextV1? {
        let offsetSeconds: Int?
        if let utcOffsetMinutes {
            let (value, overflow) = utcOffsetMinutes.multipliedReportingOverflow(by: 60)
            guard !overflow else {
                throw ObservationAndTimeValidationFailureV1.invalidTemporalContext
            }
            offsetSeconds = value
        } else {
            offsetSeconds = nil
        }
        return try TemporalContextV1(
            occurredAtUTC: observedAtUTC,
            recordedAtUTC: recordedAtUTC,
            localDate: localDate,
            localTime: localTime,
            utcOffsetSeconds: offsetSeconds,
            ianaTimeZoneIdentifier: timeZoneID,
            localTimeDisposition: .unknown
        )
    }
}

private enum ObservationAndTimeValidationV1 {
    static func isBoundedToken(_ value: String, maximumBytes: Int) -> Bool {
        guard isBoundedText(value, maximumBytes: maximumBytes) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func isBoundedText(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= maximumBytes
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    static func isBoundedTimeZoneIdentifier(_ value: String, maximumBytes: Int) -> Bool {
        isBoundedText(value, maximumBytes: maximumBytes)
    }

    static func isISODate(_ value: String) -> Bool {
        guard value.utf8.count == 10 else { return false }
        let bytes = Array(value.utf8)
        guard bytes[4] == 45 && bytes[7] == 45
            && bytes.enumerated().allSatisfy { index, byte in
                index == 4 || index == 7 || (48...57).contains(byte)
            },
              let year = decimal(bytes[0...3]),
              let month = decimal(bytes[5...6]),
              let day = decimal(bytes[8...9]),
              (1...9_999).contains(year),
              (1...12).contains(month),
              (1...31).contains(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return false }
        calendar.timeZone = utc
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = utc
        components.year = year
        components.month = month
        components.day = day
        guard let instant = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: instant)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    static func isISOTime(_ value: String) -> Bool {
        guard value.utf8.count == 8 else { return false }
        let bytes = Array(value.utf8)
        guard bytes[2] == 58 && bytes[5] == 58
            && bytes.enumerated().allSatisfy { index, byte in
                index == 2 || index == 5 || (48...57).contains(byte)
            },
              let hour = decimal(bytes[0...1]),
              let minute = decimal(bytes[3...4]),
              let second = decimal(bytes[6...7]) else { return false }
        return (0...23).contains(hour)
            && (0...59).contains(minute)
            && (0...59).contains(second)
    }

    private static func decimal(_ bytes: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for byte in bytes {
            guard (48...57).contains(byte) else { return nil }
            value = value * 10 + Int(byte - 48)
        }
        return value
    }
}

private extension Data {
    func boundedObservationAndTimeData() throws -> Data {
        guard !isEmpty,
              count <= ObservationAndTimeSchemaV1.maximumEncodedValueBytes else {
            throw ObservationAndTimeValidationFailureV1.encodedValueTooLarge
        }
        return self
    }
}

enum LightingObservationTimeEnrollmentV1 { static let lightingRecordedAtUsesCanonicalDateEncoding = true; static let originalObservationBasisIsReferencedNotCopied = true }

enum C31LightingObservationTimeBoundaryV1 {
    static let recordedTimeDoesNotDeriveDarkness = true
    static let timezoneAndOffsetRemainRecordedContext = true
    static let observationSourceRemainsSeparateFromMeasurement = true
}
// MARK: - C32 assistance observation and time boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_ObservationAndTimeModelsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let deviceObservationProposalIsNotTimeFact = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row119 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Models_ObservationAndTimeModelsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}
