import Foundation
import XCTest
@testable import FieldEvidenceApp

private final class C45EvidenceContextCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityMakesDisclosurePurposeExplicit() {
        XCTAssertEqual(Set(LabelDisclosureProfileV1.allCases), [.shortCodeOnly, .assetAndShortCode, .assetLocationAndShortCode])
        XCTAssertNotEqual(LabelDisclosureProfileV1.shortCodeOnly, .assetAndShortCode)
        XCTAssertNotEqual(LabelDisclosureProfileV1.assetAndShortCode, .assetLocationAndShortCode)
    }
}

private enum C30EvidenceContextTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_785_000_000)
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c3000000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(100 + slot))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(1_000 + slot))
    }

    static func digest(_ character: Character = "a") -> String {
        String(repeating: String(character), count: 64)
    }

    static func actor(
        workspaceID: WorkspaceID,
        slot: Int,
        responsibility: ResponsibilityKindV1 = .recordedBy
    ) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(
            actorReferenceID: id(2_000 + slot),
            workspaceID: workspaceID,
            displayName: "C30 local recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: id(3_000 + slot),
            workspaceID: workspaceID,
            actor: local,
            responsibility: responsibility,
            displayNameAtTime: local.displayName,
            capturedAt: fixedDate
        )
    }

    static func temporal(
        occurredAt: Date? = fixedDate,
        recordedAt: Date = fixedDate.addingTimeInterval(2),
        timeZone: String? = "UTC",
        offset: Int? = 0,
        disposition: LocalTimeDispositionV1 = .unambiguous
    ) throws -> TemporalContextV1 {
        try TemporalContextV1(
            occurredAtUTC: occurredAt,
            recordedAtUTC: recordedAt,
            localDate: "2026-08-29",
            localTime: "12:00:00",
            utcOffsetSeconds: offset,
            ianaTimeZoneIdentifier: timeZone,
            localTimeDisposition: disposition
        )
    }

    static func location(
        latitude: Int32 = 40_000_000,
        longitude: Int32 = -74_000_000,
        digestCharacter: Character = "a"
    ) throws -> SolarLocationV1 {
        try SolarLocationV1(
            latitudeMicrodegrees: latitude,
            longitudeMicrodegrees: longitude,
            locationBasisSHA256: digest(digestCharacter)
        )
    }

    static func solar(
        latitude: Int32 = 40_000_000,
        longitude: Int32 = -74_000_000,
        temporal: TemporalContextV1? = nil
    ) throws -> DerivedSolarContextV1 {
        let time = try temporal ?? self.temporal()
        return try OfflineSolarCalculatorV1.calculate(
            SolarCalculationInputV1(
                location: try location(latitude: latitude, longitude: longitude),
                temporalContext: time
            )
        )
    }

    static func context(
        workspaceID: WorkspaceID,
        evidenceID: String,
        assetID: UUID,
        condition: EvidenceLightingConditionV1,
        temporal: TemporalContextV1? = nil,
        derivedSolar: DerivedSolarContextV1? = nil,
        controlExpectation: ControlExpectationV1? = nil,
        predecessor: EvidenceContextV1? = nil,
        revision: UInt64 = 1,
        recordedAt: Date? = nil,
        mutationSlot: Int,
        contextSlot: Int
    ) throws -> EvidenceContextV1 {
        let time = try temporal ?? self.temporal()
        return try EvidenceContextV1(
            contextID: id(contextSlot),
            workspaceID: workspaceID,
            evidenceID: evidenceID,
            evidenceSHA256: digest("f"),
            evidenceRevision: 1,
            assetID: assetID,
            assetRevision: 1,
            temporalContext: time,
            userObserved: try UserObservedEvidenceContextV1(
                condition: condition,
                observationNoteCode: "C30_USER_OBSERVED"
            ),
            derivedSolar: derivedSolar,
            controlExpectation: controlExpectation,
            predecessor: predecessor,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            recordedBy: try actor(workspaceID: workspaceID, slot: contextSlot),
            recordedAt: recordedAt ?? time.recordedAtUTC.addingTimeInterval(1)
        )
    }

    static func control(
        state: ExpectedControlStateV1 = .noExpectation,
        policyCharacter: Character = "b"
    ) throws -> ControlExpectationV1 {
        try ControlExpectationV1(
            controlGroupID: "C30_CONTROL_GROUP",
            expectedState: state,
            policyID: "C30_LOCAL_POLICY",
            policyVersion: 1,
            policySHA256: digest(policyCharacter)
        )
    }

    static func reference(
        _ context: EvidenceContextV1,
        purpose: PairedObservationPurposeV1 = .conditionComparison,
        controlGroupID: String = "C30_CONTROL_GROUP",
        assetRevision: UInt64? = nil,
        planCharacter: Character = "c",
        viewpointCharacter: Character = "d",
        bucket: String = "C30_BUCKET",
        weatherCharacter: Character = "e",
        method: String = "C30_MANUAL_OBSERVATION"
    ) throws -> PairedObservationReferenceV1 {
        try PairedObservationReferenceV1(
            evidenceID: context.evidenceID,
            evidenceSHA256: context.contextSHA256,
            evidenceRevision: context.evidenceRevision,
            assetID: context.assetID,
            assetRevision: assetRevision ?? context.assetRevision,
            controlGroupID: controlGroupID,
            purpose: purpose,
            purposeRevision: 1,
            planReferenceSHA256: planCharacter == "_" ? nil : digest(planCharacter),
            viewpointReferenceSHA256: digest(viewpointCharacter),
            temporalBucketID: bucket,
            surfaceWeatherBasisSHA256: digest(weatherCharacter),
            measurementMethodID: method
        )
    }

    static func pair(
        workspaceID: WorkspaceID,
        first: PairedObservationReferenceV1,
        second: PairedObservationReferenceV1,
        predecessor: PairedObservationLinkV1? = nil,
        revision: UInt64 = 1,
        mutationSlot: Int,
        linkSlot: Int
    ) throws -> PairedObservationLinkV1 {
        try PairedObservationLinkV1(
            linkID: id(linkSlot),
            workspaceID: workspaceID,
            first: first,
            second: second,
            predecessor: predecessor,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            recordedBy: try actor(workspaceID: workspaceID, slot: linkSlot),
            recordedAt: fixedDate.addingTimeInterval(3)
        )
    }
}

private struct C30EvidenceContextCorpus: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let recordsSchemaVersion: Int
    let persistentSchemaVersion: Int
    let durableFamilies: [String]
    let durableFamilyCount: Int
    let lightingConditions: [String]
    let polarDispositions: [String]
    let mismatchReasons: [String]
    let lifecycleDimensions: [String]
    let exclusions: [String]
    let correctionHostiles: [String]
}

@MainActor
final class V9_45EvidenceContextTests: XCTestCase {
    private func loadCorpus() throws -> C30EvidenceContextCorpus {
        let bundle = Bundle(for: V9_45EvidenceContextTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C30EvidenceContextCorpusV1",
                withExtension: "json",
                subdirectory: "EvidenceContext"
            )
        )
        return try JSONDecoder().decode(
            C30EvidenceContextCorpus.self,
            from: Data(contentsOf: url)
        )
    }

    func testV23P03C30G01ExplicitConditionsAndOfflineSolarDerivationAreDeterministic() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schema, "V22P03C30EvidenceContextCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C30")
        XCTAssertEqual(corpus.recordsSchemaVersion, EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion)
        XCTAssertEqual(corpus.persistentSchemaVersion, EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion)
        XCTAssertEqual(corpus.durableFamilyCount, EvidenceContextPersistenceEnrollmentV1.durableModelCount)
        XCTAssertEqual(corpus.durableFamilies, ["EvidenceContextV1", "PairedObservationLinkV1"])
        XCTAssertEqual(Set(corpus.lightingConditions), Set(EvidenceLightingConditionV1.allCases.map(\.rawValue)))

        let temporal = try C30EvidenceContextTestSupport.temporal()
        let input = try SolarCalculationInputV1(
            location: try C30EvidenceContextTestSupport.location(),
            temporalContext: temporal
        )
        let first = try OfflineSolarCalculatorV1.calculate(input)
        let second = try OfflineSolarCalculatorV1.calculate(input)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.calculationVersion, DerivedSolarContextV1.currentCalculationVersion)
        XCTAssertEqual(first.polarDisposition, .ordinary)
        XCTAssertNotNil(first.sunrise)
        XCTAssertNotNil(first.sunset)
        XCTAssertNotNil(first.civilTwilightDawn)
        XCTAssertNotNil(first.civilTwilightDusk)
        try first.validate()

        let workspace = C30EvidenceContextTestSupport.workspace()
        let context = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_DAYLIGHT_EVIDENCE",
            assetID: C30EvidenceContextTestSupport.id(10),
            condition: .daylight,
            temporal: temporal,
            derivedSolar: first,
            controlExpectation: try C30EvidenceContextTestSupport.control(state: .expectedOperating),
            mutationSlot: 11,
            contextSlot: 12
        )
        let bytes = try EvidenceContextCanonicalCodecV1.encode(context)
        XCTAssertEqual(
            try EvidenceContextCanonicalCodecV1.decode(EvidenceContextV1.self, from: bytes),
            context
        )
        XCTAssertEqual(try EvidenceContextRow(context).value(), context)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
    }

    func testV23P03C30A01CoveredAndUnknownContextsRetainUserTruthAndStablePairing() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(Set(corpus.polarDispositions), Set(SolarPolarDispositionV1.allCases.map(\.rawValue)))
        XCTAssertEqual(corpus.exclusions.count, 6)

        let workspace = C30EvidenceContextTestSupport.workspace()
        let assetID = C30EvidenceContextTestSupport.id(20)
        let covered = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_COVERED_GARAGE",
            assetID: assetID,
            condition: .coveredNightCondition,
            derivedSolar: nil,
            controlExpectation: try C30EvidenceContextTestSupport.control(),
            mutationSlot: 21,
            contextSlot: 22
        )
        let unknown = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_UNKNOWN_CONTEXT",
            assetID: assetID,
            condition: .unknown,
            derivedSolar: nil,
            controlExpectation: try C30EvidenceContextTestSupport.control(),
            mutationSlot: 23,
            contextSlot: 24
        )
        XCTAssertEqual(covered.userObserved.condition, .coveredNightCondition)
        XCTAssertEqual(unknown.userObserved.condition, .unknown)
        XCTAssertEqual(unknown.controlExpectation?.expectedState, .noExpectation)
        XCTAssertNil(covered.derivedSolar)

        let first = try C30EvidenceContextTestSupport.reference(covered)
        let second = try C30EvidenceContextTestSupport.reference(unknown)
        let link = try C30EvidenceContextTestSupport.pair(
            workspaceID: workspace,
            first: first,
            second: second,
            mutationSlot: 25,
            linkSlot: 26
        )
        try link.validateCompatiblePair()
        XCTAssertTrue(link.mismatchReasons.isEmpty)
        XCTAssertEqual(
            try EvidenceContextCanonicalCodecV1.decode(
                PairedObservationLinkV1.self,
                from: EvidenceContextCanonicalCodecV1.encode(link)
            ),
            link
        )
        XCTAssertEqual(try PairedObservationLinkRow(link).value(), link)

        let successor = try C30EvidenceContextTestSupport.pair(
            workspaceID: workspace,
            first: first,
            second: second,
            predecessor: link,
            revision: 2,
            mutationSlot: 27,
            linkSlot: 28
        )
        try successor.validateSuccessor(of: link)
        XCTAssertEqual(successor.predecessorLinkSHA256, link.linkSHA256)
    }

    func testV23P03C30H01MissingLocationTimeConflictsAndPurposeMismatchFailClosed() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(
            Set(corpus.correctionHostiles),
            Set([
                "INVALID_TIME_ZONE", "OFFSET_CONFLICT", "EXTREME_FINITE_DATE",
                "INT64_CONVERSION_OVERFLOW", "DANGLING_PAIRED_ENDPOINT",
                "REPORT_ZERO_UUID", "REPORT_LINK_IDENTITY_MISMATCH",
                "CONFLICTING_COMPARISON_PURPOSE"
            ])
        )
        let invalidTimeZone = try C30EvidenceContextTestSupport.temporal(
            timeZone: "Mars/NotAZone",
            offset: 0
        )
        XCTAssertThrowsError(
            try EvidenceContextLimitsV1.validateTimeZoneIfDeclared(in: invalidTimeZone)
        )
        XCTAssertThrowsError(
            try OfflineSolarCalculatorV1.calculate(
                SolarCalculationInputV1(
                    location: C30EvidenceContextTestSupport.location(),
                    temporalContext: invalidTimeZone
                )
            )
        )
        let offsetConflict = try C30EvidenceContextTestSupport.temporal(
            timeZone: "America/New_York",
            offset: 0
        )
        XCTAssertThrowsError(
            try EvidenceContextLimitsV1.validateTimeZoneIfDeclared(in: offsetConflict)
        )
        XCTAssertThrowsError(
            try OfflineSolarCalculatorV1.calculate(
                SolarCalculationInputV1(
                    location: C30EvidenceContextTestSupport.location(),
                    temporalContext: offsetConflict
                )
            )
        )
        let extremeFiniteDate = Date(timeIntervalSince1970: Double.greatestFiniteMagnitude)
        XCTAssertTrue(extremeFiniteDate.timeIntervalSince1970.isFinite)
        XCTAssertThrowsError(try EvidenceContextLimitsV1.exactInt64(Double.greatestFiniteMagnitude))
        XCTAssertThrowsError(try EvidenceContextLimitsV1.utcEpochSecond(extremeFiniteDate))
        XCTAssertThrowsError(
            try EvidenceContextLimitsV1.utcEpochSecond(
                Date(timeIntervalSince1970: Double(Int64.max))
            )
        )
        XCTAssertThrowsError(try C30EvidenceContextTestSupport.location(latitude: 90_000_001))
        XCTAssertThrowsError(try C30EvidenceContextTestSupport.location(longitude: 180_000_001))
        XCTAssertThrowsError(
            try SolarCalculationInputV1(
                location: C30EvidenceContextTestSupport.location(),
                temporalContext: C30EvidenceContextTestSupport.temporal(
                    timeZone: nil,
                    offset: 0
                )
            )
        )
        XCTAssertThrowsError(
            try SolarCalculationInputV1(
                location: C30EvidenceContextTestSupport.location(),
                temporalContext: C30EvidenceTestTemporal.ambiguous()
            )
        )
        XCTAssertThrowsError(
            try SolarCalculationInputV1(
                location: C30EvidenceContextTestSupport.location(),
                temporalContext: C30EvidenceTestTemporal.gap()
            )
        )

        let workspace = C30EvidenceContextTestSupport.workspace(2)
        let assetID = C30EvidenceContextTestSupport.id(30)
        let firstContext = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_FIRST",
            assetID: assetID,
            condition: .daylight,
            mutationSlot: 31,
            contextSlot: 32
        )
        let secondContext = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_SECOND",
            assetID: assetID,
            condition: .night,
            mutationSlot: 33,
            contextSlot: 34
        )
        let first = try C30EvidenceContextTestSupport.reference(firstContext)
        let allChanged = try C30EvidenceContextTestSupport.reference(
            secondContext,
            purpose: .controlStateComparison,
            controlGroupID: "C30_OTHER_GROUP",
            assetRevision: 2,
            planCharacter: "f",
            viewpointCharacter: "a",
            bucket: "C30_OTHER_BUCKET",
            weatherCharacter: "b",
            method: "C30_IMPORTED_METHOD"
        )
        let reasons = PairedObservationLinkV1.mismatches(first, allChanged)
        XCTAssertEqual(Set(reasons), Set(PairedObservationMismatchReasonV1.allCases))
        XCTAssertThrowsError(
            try C30EvidenceContextTestSupport.pair(
                workspaceID: workspace,
                first: first,
                second: allChanged,
                mutationSlot: 35,
                linkSlot: 36
            ).validateCompatiblePair()
        )
        let replacementAsset = try C30EvidenceContextTestSupport.reference(
            try C30EvidenceContextTestSupport.context(
                workspaceID: workspace,
                evidenceID: "C30_REPLACEMENT_ASSET",
                assetID: C30EvidenceContextTestSupport.id(39),
                condition: .night,
                mutationSlot: 39,
                contextSlot: 390
            ),
            controlGroupID: first.controlGroupID,
            assetRevision: 2
        )
        XCTAssertTrue(PairedObservationLinkV1.mismatches(first, replacementAsset).contains(.controlMismatch))
        XCTAssertTrue(PairedObservationLinkV1.mismatches(first, replacementAsset).contains(.assetRevisionMismatch))

        let backupLink = try C30EvidenceContextTestSupport.pair(
            workspaceID: workspace,
            first: first,
            second: try C30EvidenceContextTestSupport.reference(secondContext),
            mutationSlot: 55,
            linkSlot: 56
        )
        let danglingRecord = try C30EvidenceContextBackupEncoderV1.encode(backupLink)
        XCTAssertThrowsError(
            try C30EvidenceContextBackupDecoderV1.decode([danglingRecord])
        )

        let report = try C30EvidenceContextReportReferenceV1(context: firstContext, pairedObservation: backupLink)
        var reportObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        )
        reportObject["contextID"] = C30EvidenceContextTestSupport.zeroUUID.uuidString
        let zeroReport = try JSONDecoder().decode(
            C30EvidenceContextReportReferenceV1.self,
            from: JSONSerialization.data(withJSONObject: reportObject, options: [.sortedKeys])
        )
        XCTAssertThrowsError(try zeroReport.validate())

        let pairedReport = try C30PairedObservationReportReferenceV1(
            backupLink,
            context: firstContext
        )
        var pairedReportObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(pairedReport)) as? [String: Any]
        )
        pairedReportObject["linkID"] = C30EvidenceContextTestSupport.zeroUUID.uuidString
        let zeroLinkReport = try JSONDecoder().decode(
            C30PairedObservationReportReferenceV1.self,
            from: JSONSerialization.data(withJSONObject: pairedReportObject, options: [.sortedKeys])
        )
        XCTAssertThrowsError(try zeroLinkReport.validate())

        let foreignContext = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_FOREIGN_ENDPOINT",
            assetID: assetID,
            condition: .unknown,
            mutationSlot: 57,
            contextSlot: 58
        )
        let foreignLink = try C30EvidenceContextTestSupport.pair(
            workspaceID: workspace,
            first: try C30EvidenceContextTestSupport.reference(secondContext),
            second: try C30EvidenceContextTestSupport.reference(foreignContext),
            mutationSlot: 59,
            linkSlot: 60
        )
        XCTAssertThrowsError(
            try C30EvidenceContextReportReferenceV1(
                context: firstContext,
                pairedObservation: foreignLink
            )
        )

        let purposeContext = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_PURPOSE_THIRD",
            assetID: assetID,
            condition: .unknown,
            mutationSlot: 61,
            contextSlot: 62
        )
        let conditionPair = try C30EvidenceContextTestSupport.pair(
            workspaceID: workspace,
            first: try C30EvidenceContextTestSupport.reference(
                firstContext,
                purpose: .conditionComparison
            ),
            second: try C30EvidenceContextTestSupport.reference(
                secondContext,
                purpose: .conditionComparison
            ),
            mutationSlot: 63,
            linkSlot: 64
        )
        let controlPair = try C30EvidenceContextTestSupport.pair(
            workspaceID: workspace,
            first: try C30EvidenceContextTestSupport.reference(
                firstContext,
                purpose: .controlStateComparison
            ),
            second: try C30EvidenceContextTestSupport.reference(
                purposeContext,
                purpose: .controlStateComparison
            ),
            mutationSlot: 65,
            linkSlot: 66
        )
        let purposeRows = try C30EvidenceContextBackupEncoderV1.encode(
            EvidenceContextBackupRecordSetV1(
                contexts: [firstContext, secondContext, purposeContext],
                pairedObservationLinks: [conditionPair, controlPair]
            )
        )
        XCTAssertThrowsError(
            try C30EvidenceContextBackupDecoderV1.decode(purposeRows)
        )

        XCTAssertThrowsError(
            try C30EvidenceContextTestSupport.context(
                workspaceID: workspace,
                evidenceID: "C30_CLOCK_CORRECTED",
                assetID: assetID,
                condition: .daylight,
                temporal: try C30EvidenceContextTestSupport.temporal(
                    recordedAt: C30EvidenceContextTestSupport.fixedDate.addingTimeInterval(2)
                ),
                recordedAt: C30EvidenceContextTestSupport.fixedDate.addingTimeInterval(1),
                mutationSlot: 37,
                contextSlot: 38
            )
        )
        let explicit = try UserObservedEvidenceContextV1(condition: .unknown)
        XCTAssertEqual(explicit.source, .userObserved)
        XCTAssertTrue(C30EvidenceContextTestSupport.digest().count == 64)
    }

    func testV23P03C30I01InterruptedContextAndPairWritesRecoverAsZeroOrOneCanonicalSuccess() throws {
        let workspace = C30EvidenceContextTestSupport.workspace(3)
        let assetID = C30EvidenceContextTestSupport.id(40)
        let first = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_INTERRUPTION",
            assetID: assetID,
            condition: .civilTwilight,
            mutationSlot: 41,
            contextSlot: 42
        )
        let successor = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: first.evidenceID,
            assetID: assetID,
            condition: .night,
            predecessor: first,
            revision: 2,
            mutationSlot: 43,
            contextSlot: 44
        )
        let append = EvidenceContextWriteOperationV1.appendContext(value: first, predecessor: nil)
        let appendSuccessor = EvidenceContextWriteOperationV1.appendContext(value: successor, predecessor: first)
        try append.validate()
        try appendSuccessor.validate()
        XCTAssertEqual(append.mutationID, first.mutationID)
        XCTAssertEqual(appendSuccessor.expectedRevision, 1)

        // An effect written before its receipt may be replayed only with the
        // exact predecessor; a retry that omits it must fail closed.
        XCTAssertThrowsError(
            try EvidenceContextWriteOperationV1.appendContext(value: successor, predecessor: nil).validate()
        )
        XCTAssertThrowsError(
            try EvidenceContextWriteOperationV1.appendContext(value: first, predecessor: first).validate()
        )

        let firstReference = try C30EvidenceContextTestSupport.reference(first)
        let secondReference = try C30EvidenceContextTestSupport.reference(
            try C30EvidenceContextTestSupport.context(
                workspaceID: workspace,
                evidenceID: "C30_INTERRUPTION_SECOND",
                assetID: assetID,
                condition: .coveredDayCondition,
                mutationSlot: 45,
                contextSlot: 46
            )
        )
        let link = try C30EvidenceContextTestSupport.pair(
            workspaceID: workspace,
            first: firstReference,
            second: secondReference,
            mutationSlot: 47,
            linkSlot: 48
        )
        let pairOperation = EvidenceContextWriteOperationV1.appendPair(value: link, predecessor: nil)
        try pairOperation.validate()
        XCTAssertEqual(pairOperation.expectedRevision, 0)
        XCTAssertEqual(pairOperation.semanticSHA256, link.linkSHA256)
        XCTAssertTrue(try pairOperation.affectedIdentity.kind == .pairedObservationLink)
    }

    func testV23P03C30R01RestoreReplayRebuildAndHistoricContextRemainByteExact() throws {
        let workspace = C30EvidenceContextTestSupport.workspace(4)
        let context = try C30EvidenceContextTestSupport.context(
            workspaceID: workspace,
            evidenceID: "C30_HISTORIC",
            assetID: C30EvidenceContextTestSupport.id(50),
            condition: .night,
            derivedSolar: try C30EvidenceContextTestSupport.solar(latitude: 89_000_000),
            controlExpectation: try C30EvidenceContextTestSupport.control(state: .noExpectation),
            mutationSlot: 51,
            contextSlot: 52
        )
        let bytes = try EvidenceContextCanonicalCodecV1.encode(context)
        let restored = try EvidenceContextCanonicalCodecV1.decode(EvidenceContextV1.self, from: bytes)
        XCTAssertEqual(restored, context)
        XCTAssertEqual(try EvidenceContextCanonicalCodecV1.encode(restored), bytes)

        let row = try EvidenceContextRow(context)
        XCTAssertEqual(try row.value(), context)
        let clone = try context.rebound(
            to: C30EvidenceContextTestSupport.workspace(5),
            predecessor: nil,
            recordedBy: C30EvidenceContextTestSupport.actor(
                workspaceID: C30EvidenceContextTestSupport.workspace(5),
                slot: 53
            )
        )
        XCTAssertEqual(clone.contextID, context.contextID)
        XCTAssertEqual(clone.evidenceID, context.evidenceID)
        XCTAssertNotEqual(clone.workspaceID, context.workspaceID)
        XCTAssertNotEqual(clone.contextSHA256, context.contextSHA256)

        let polar = try C30EvidenceContextTestSupport.solar(latitude: 89_000_000)
        XCTAssertNotEqual(polar.polarDisposition, .ordinary)
        XCTAssertNil(polar.sunrise)
        XCTAssertNil(polar.sunset)
        XCTAssertNil(polar.civilTwilightDawn)
        XCTAssertNil(polar.civilTwilightDusk)
        XCTAssertTrue(
            [DerivedSolarConditionV1.daylight, .night, .unknown].contains(polar.derivedCondition)
        )

        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.totalModelCount, 104)
    }
}

private enum C30EvidenceTestTemporal {
    static func ambiguous() throws -> TemporalContextV1 {
        try TemporalContextV1(
            occurredAtUTC: C30EvidenceContextTestSupport.fixedDate,
            recordedAtUTC: C30EvidenceContextTestSupport.fixedDate.addingTimeInterval(2),
            localDate: "2026-11-01",
            localTime: "01:30:00",
            utcOffsetSeconds: -14_400,
            ianaTimeZoneIdentifier: "America/New_York",
            localTimeDisposition: .ambiguousFold
        )
    }

    static func gap() throws -> TemporalContextV1 {
        try TemporalContextV1(
            occurredAtUTC: nil,
            recordedAtUTC: C30EvidenceContextTestSupport.fixedDate.addingTimeInterval(2),
            localDate: "2026-03-08",
            localTime: "02:30:00",
            utcOffsetSeconds: nil,
            ianaTimeZoneIdentifier: "America/New_York",
            localTimeDisposition: .nonexistentGap
        )
    }
}
private final class C31LightingAnchorV945EvidenceContextTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV945EvidenceContext: XCTestCase {
    func testC33V945EvidenceContextCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "context.temporal-evidence-binding",
            kind: .audio,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "context.temporal-evidence-binding",
            kind: .audio,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV945EvidenceContext: XCTestCase {
    func testC32V945EvidenceContextCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .evidenceContext,
            fieldID: "evidence-context.unverified",
            value: .singleOption("UNVERIFIED")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .evidenceContext,
            fieldID: "evidence-context.unverified",
            valueKind: .singleOption
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V945EvidenceCompatibilityTests: XCTestCase {
    func testC46EvidenceContextDoesNotBecomeContactProvenance() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "evidence-context",
            kind: .email,
            handoff: .email,
            slot: 46045
        )
    }
}
