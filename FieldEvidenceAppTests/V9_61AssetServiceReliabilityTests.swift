import Foundation
import XCTest

@testable import FieldEvidenceApp

/// Shared by the C53 cross-cutting anchors.  Keeping the anchor typed makes
/// every incumbent test compile against the same reliability contract rather
/// than carrying a string-only card marker.
enum C53AssetServiceReliabilityBoundaryTokenV1 {
    static let cardID = "V23-P03-C53"
    static let evidenceIDs = [
        "V23-P03-C53-G01",
        "V23-P03-C53-A01",
        "V23-P03-C53-H01",
        "V23-P03-C53-I01",
        "V23-P03-C53-R01",
    ]
    static let impactKinds = ServiceImpactKindV1.allCases.map(\.rawValue)
    static let origins = ServiceImpactOriginV1.allCases.map(\.rawValue)
    static let coverageStates = ServiceReliabilityCoverageV1.allCases.map(\.rawValue)
}

private struct C53ServiceReliabilityCorpusFixture: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let corpusID: String
    let testOnly: Bool
    let synthetic: Bool
    let immutable: Bool
    let containsCustomerData: Bool
    let containsSecrets: Bool
    let contracts: [String]
    let evidenceIDs: [String]
    let impactKinds: [String]
    let origins: [String]
    let coverageStates: [String]
    let golden: C53ScenarioFixture
    let alternate: C53ScenarioFixture
    let hostileCases: [String]
    let lifecycle: C53LifecycleFixture
    let claims: C53ClaimsFixture
    let typedAnchor: String
}

private struct C53ScenarioFixture: Decodable {
    let exposureSeconds: Int
    let plannedExclusionSeconds: Int
    let downtimeSeconds: Int
    let operatingSeconds: Int
    let maximalDowntimeComponents: Int
    let qualifyingFailureStarts: Int
    let degradedAndIntermittentAreUnweighted: Bool
    let unavailableReasons: [String]
}

private struct C53LifecycleFixture: Decodable {
    let appendOnly: Bool
    let expectedRevision: Bool
    let oneWriter: Bool
    let durableReceipt: Bool
    let backupRestore: Bool
    let cloneForkInvalidation: Bool
    let journalReplay: Bool
    let projectionRebuild: Bool
    let erasePrivacy: Bool
    let compatibility: Bool
}

private struct C53ClaimsFixture: Decodable {
    let restorationIsNotReleaseToService: Bool
    let restorationIsNotSafetyOrCompliance: Bool
    let mttrLabel: String
    let degradedAndIntermittentHaveNoWeight: Bool
    let telemetryAndPredictionAbsent: Bool
}

private actor C53LifecycleProbe {
    private var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private enum C53AssetServiceReliabilityTestSupport {
    static let workspace = WorkspaceID(rawValue: UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5401")!)
    static let siteID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5402")!
    static let assetID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5403")!
    static let incidentID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5404")!
    static let generationID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5405")!
    static let writerInstanceID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5406")!
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func uuid(_ value: String) -> UUID { UUID(uuidString: value)! }

    static func mutation(_ value: String) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: uuid(value))
    }

    static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }

    static func instant(_ seconds: Int64) -> ServiceReliabilityInstantV1 {
        ServiceReliabilityInstantV1(millisecondsSince1970: seconds * 1_000)
    }

    static func interval(_ lower: Int64, _ upper: Int64) throws -> ServiceReliabilityClosedIntervalV1 {
        try ServiceReliabilityClosedIntervalV1(lowerBound: instant(lower), upperBound: instant(upper))
    }

    static func observation() throws -> ObservationBasisV1 {
        try ObservationBasisV1(
            kind: .directlyObserved,
            method: try ObservationMethodV1(key: "C53_TYPED_TEST"),
            source: try ObservationSourceReferenceV1(kind: .observer)
        )
    }

    static func temporal(at seconds: TimeInterval) throws -> TemporalContextV1 {
        let date = Date(timeIntervalSince1970: seconds)
        return try TemporalContextV1(
            occurredAtUTC: date,
            recordedAtUTC: date,
            localDate: nil,
            localTime: nil,
            utcOffsetSeconds: nil,
            ianaTimeZoneIdentifier: nil,
            localTimeDisposition: .unknown
        )
    }

    static func actor() throws -> ActorSnapshotV1 {
        let actor = try LocalActorReferenceV1(
            actorReferenceID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5407"),
            workspaceID: workspace,
            displayName: "C53 Typed Test Actor"
        )
        return try ActorSnapshotV1(
            snapshotID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5408"),
            workspaceID: workspace,
            actor: actor,
            responsibility: .recordedBy,
            displayNameAtTime: actor.displayName,
            capturedAt: fixedDate
        )
    }

    static func contentReference() throws -> ContentReferenceV1 {
        let contentDigest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: digest("d")
        )
        return try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: "c53-evidence",
            byteLength: 12,
            mediaType: "text/plain",
            digests: try ContentDigestSetV1([contentDigest]),
            byteRole: .immutableOriginal,
            createdAt: "2026-08-27T00:00:00.000Z"
        )
    }

    static func subject() throws -> ServiceReliabilitySubjectV1 {
        let package = try PackageReleaseIdentityV1(
            packageID: "com.field-evidence.c53.reliability",
            schemaVersion: 1,
            contentVersion: 1
        )
        let catalog = AssetSemanticCatalogReleaseReferenceV1(
            releaseID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5409"),
            packageRelease: package,
            catalogSHA256: digest("a")
        )
        let asset = WorkSubjectReferenceV1(
            kind: .asset,
            subjectID: assetID,
            revision: 1,
            ownerAssetID: nil
        )
        let binding = try WorkSubjectSemanticBindingSnapshotV1(
            assetID: assetID,
            kindBindingEventID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5410"),
            kindBindingRevision: 1,
            catalogRelease: catalog,
            semanticID: "asset.kind.c53.reliability",
            workflowPackageReleases: [package]
        )
        let scope = try WorkSubjectScopeSnapshotV1(
            snapshotID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5411"),
            workspaceID: workspace,
            siteID: siteID,
            subjects: [asset],
            semanticBindings: [binding],
            workspaceRevision: 1,
            recordedAt: fixedDate
        )
        return ServiceReliabilitySubjectV1(
            asset: asset,
            frozenScope: scope,
            function: nil,
            reliabilityIdentityEpochID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5412")
        )
    }

    static func exposure(
        subject: ServiceReliabilitySubjectV1,
        lower: Int64 = 0,
        upper: Int64 = 100,
        plannedExclusions: [ServiceReliabilityClosedIntervalV1] = [],
        coverage: ServiceReliabilityCoverageV1 = .complete,
        mutationID: MutationIDV1? = nil,
        eventID: UUID? = nil
    ) throws -> QualifiedServiceExposureV1 {
        let interval = try self.interval(lower, upper)
        return try QualifiedServiceExposureV1(
            eventID: eventID ?? uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5413"),
            exposureID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5414"),
            workspaceID: workspace,
            subject: subject,
            interval: interval,
            declaredCoverageWindow: interval,
            coverage: coverage,
            plannedNonserviceExclusions: plannedExclusions,
            source: .acceptedRecord,
            observationBasis: try observation(),
            timeBasis: try temporal(at: fixedDate.timeIntervalSince1970),
            sourceNote: "C53 deterministic fixture",
            recordedBy: try actor(),
            revision: 1,
            mutationID: mutationID ?? (try mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5415"))
        )
    }

    static func segment(
        subject: ServiceReliabilitySubjectV1,
        impact: ServiceImpactKindV1,
        origin: ServiceImpactOriginV1,
        lower: Int64?,
        upper: Int64?,
        transitionID: UUID? = uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5416"),
        certainty: ServiceTimeCertaintyV1 = .exact,
        segmentID: UUID? = nil,
        incidentID: UUID = C53AssetServiceReliabilityTestSupport.incidentID,
        evidence: [ContentReferenceV1] = [],
        eventID: UUID,
        mutationID: MutationIDV1
    ) throws -> ServiceImpactSegmentV1 {
        let closed = try lower.map { value in try interval(value, upper!) }
        return try ServiceImpactSegmentV1(
            eventID: eventID,
            segmentID: segmentID ?? eventID,
            incidentID: incidentID,
            workspaceID: workspace,
            subject: subject,
            impact: impact,
            origin: origin,
            interval: closed,
            openedAt: instant(lower ?? 0),
            certainty: certainty,
            transitionIntoImpactEventID: transitionID,
            observationBasis: try observation(),
            recordedTime: try temporal(at: fixedDate.timeIntervalSince1970 + Double(lower ?? 0)),
            recordedBy: try actor(),
            evidence: evidence,
            revision: 1,
            mutationID: mutationID
        )
    }

    static func restoration(
        subject: ServiceReliabilitySubjectV1,
        restoredAt: Int64,
        incidentID: UUID = C53AssetServiceReliabilityTestSupport.incidentID
    ) throws -> ServiceRestorationAssertionV1 {
        try ServiceRestorationAssertionV1(
            eventID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A1"),
            assertionID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A2"),
            incidentID: incidentID,
            workspaceID: workspace,
            subject: subject,
            restoredAt: instant(restoredAt),
            certainty: .exact,
            observationBasis: try observation(),
            recordedTime: try temporal(at: fixedDate.timeIntervalSince1970 + Double(restoredAt)),
            recordedBy: try actor(),
            revision: 1,
            mutationID: mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A3")
        )
    }

    static func repair(subject: ServiceReliabilitySubjectV1) throws -> ServiceRepairIntervalV1 {
        try ServiceRepairIntervalV1(
            eventID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A4"),
            repairID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A5"),
            incidentID: incidentID,
            workspaceID: workspace,
            subject: subject,
            interval: try interval(30, 40),
            certainty: .exact,
            completed: true,
            observationBasis: try observation(),
            recordedTime: try temporal(at: fixedDate.timeIntervalSince1970 + 40),
            recordedBy: try actor(),
            revision: 1,
            mutationID: mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A6")
        )
    }

    static func project(
        subject: ServiceReliabilitySubjectV1,
        exposures: [QualifiedServiceExposureV1],
        segments: [ServiceImpactSegmentV1],
        repairs: [ServiceRepairIntervalV1] = [],
        restorations: [ServiceRestorationAssertionV1] = []
    ) throws -> ReliabilityMetricInputProjectionV1 {
        try ServiceReliabilityProjectionEngineV1.project(
            workspaceID: workspace,
            subject: subject,
            observationWindow: try interval(0, 100),
            asOf: instant(100),
            exposures: exposures,
            segments: segments,
            repairs: repairs,
            restorations: restorations
        )
    }

    static func fixture() throws -> C53ServiceReliabilityCorpusFixture {
        let bundle = Bundle(for: V9_61AssetServiceReliabilityTests.self)
        let url = bundle.url(
            forResource: "V22P03C53AssetServiceReliabilityCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V22/ServiceReliability"
        ) ?? bundle.url(
            forResource: "V22P03C53AssetServiceReliabilityCorpusV1",
            withExtension: "json"
        )
        guard let url else { throw ServiceReliabilityFailureV1.invalidValue }
        return try JSONDecoder().decode(
            C53ServiceReliabilityCorpusFixture.self,
            from: Data(contentsOf: url)
        )
    }

    static func addJSONKey(_ data: Data, key: String, value: Any) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceReliabilityFailureV1.invalidValue
        }
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func replaceEvidenceJSONKey(_ data: Data, key: String, value: Any) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var evidence = object["evidence"] as? [[String: Any]],
              !evidence.isEmpty else {
            throw ServiceReliabilityFailureV1.invalidValue
        }
        evidence[0][key] = value
        object["evidence"] = evidence
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func nonCanonical(_ data: Data) -> Data {
        var result = data
        result.append(0x20)
        return result
    }
}

@MainActor
final class V9_61AssetServiceReliabilityTests: XCTestCase {
    func testV23P03C53G01GoldenProjectionUsesTypedExposureDowntimeAndOperatingIntervals() throws {
        let corpus = try C53AssetServiceReliabilityTestSupport.fixture()
        XCTAssertEqual(corpus.schema, "V22P03C53AssetServiceReliabilityCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, C53AssetServiceReliabilityBoundaryTokenV1.cardID)
        XCTAssertEqual(corpus.evidenceIDs, C53AssetServiceReliabilityBoundaryTokenV1.evidenceIDs)
        XCTAssertTrue(corpus.contracts.contains("AssetServiceIncidentV1"))
        XCTAssertTrue(corpus.contracts.contains("ReliabilityMetricInputProjectionV1"))
        XCTAssertTrue(corpus.contracts.contains("AssetServiceReliabilityCommitPlanV1"))
        XCTAssertTrue(corpus.contracts.contains("WorkspaceWriterV1"))
        XCTAssertEqual(corpus.typedAnchor, "V23-P03-C53-G01/A01/H01/I01/R01")
        XCTAssertTrue(corpus.testOnly && corpus.synthetic && corpus.immutable)
        XCTAssertFalse(corpus.containsCustomerData || corpus.containsSecrets)
        XCTAssertEqual(corpus.golden.exposureSeconds, 90)
        XCTAssertEqual(corpus.golden.plannedExclusionSeconds, 10)
        XCTAssertEqual(corpus.golden.downtimeSeconds, 30)
        XCTAssertEqual(corpus.golden.operatingSeconds, 60)
        XCTAssertEqual(corpus.golden.maximalDowntimeComponents, 1)
        XCTAssertEqual(corpus.golden.qualifyingFailureStarts, 1)

        let subject = try C53AssetServiceReliabilityTestSupport.subject()
        let exposure = try C53AssetServiceReliabilityTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C53AssetServiceReliabilityTestSupport.interval(10, 20)]
        )
        let firstDowntime = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unplanned,
            lower: 30,
            upper: 50,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A7"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A8")
        )
        let touchingDowntime = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unplanned,
            lower: 50,
            upper: 60,
            transitionID: nil,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54A9"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B0")
        )
        let projection = try ServiceReliabilityProjectionEngineV1.project(
            workspaceID: C53AssetServiceReliabilityTestSupport.workspace,
            subject: subject,
            observationWindow: try C53AssetServiceReliabilityTestSupport.interval(0, 100),
            asOf: C53AssetServiceReliabilityTestSupport.instant(100),
            exposures: [exposure],
            segments: [firstDowntime, touchingDowntime],
            repairs: [try C53AssetServiceReliabilityTestSupport.repair(subject: subject)],
            restorations: [try C53AssetServiceReliabilityTestSupport.restoration(subject: subject, restoredAt: 50)]
        )

        XCTAssertEqual(projection.exposureDurationMilliseconds, 90_000)
        XCTAssertEqual(projection.unplannedFullDowntimeMilliseconds, 30_000)
        XCTAssertEqual(projection.operatingExposureDurationMilliseconds, 60_000)
        XCTAssertEqual(projection.maximalDowntimeComponents.count, 1)
        XCTAssertEqual(projection.qualifyingFailureStartEventIDs.count, 1)
        XCTAssertEqual(
            projection.maximalDowntimeComponents.first?.interval,
            try C53AssetServiceReliabilityTestSupport.interval(30, 60)
        )
        XCTAssertEqual(
            projection.qualifyingFailureStartEventIDs,
            [firstDowntime.eventID]
        )
        XCTAssertEqual(projection.qualifiedRestorationIntervals.count, 1)
        XCTAssertEqual(projection.availabilityQualification, .qualified)
        XCTAssertEqual(projection.mtbfQualification, .qualified)
        XCTAssertEqual(projection.mttrQualification, .qualified)
        XCTAssertEqual(
            projection.exposure.map(\.interval),
            [try C53AssetServiceReliabilityTestSupport.interval(0, 10), try C53AssetServiceReliabilityTestSupport.interval(20, 100)]
        )
        XCTAssertEqual(
            projection.operatingExposure.map(\.interval),
            [try C53AssetServiceReliabilityTestSupport.interval(20, 30), try C53AssetServiceReliabilityTestSupport.interval(60, 100)]
        )
    }

    func testV23P03C53A01AlternateUnionsAndImpactOriginsRemainUnweighted() throws {
        let corpus = try C53AssetServiceReliabilityTestSupport.fixture()
        XCTAssertEqual(corpus.impactKinds, C53AssetServiceReliabilityBoundaryTokenV1.impactKinds)
        XCTAssertEqual(corpus.origins, C53AssetServiceReliabilityBoundaryTokenV1.origins)
        XCTAssertEqual(corpus.coverageStates, C53AssetServiceReliabilityBoundaryTokenV1.coverageStates)
        XCTAssertTrue(corpus.alternate.degradedAndIntermittentAreUnweighted)
        XCTAssertEqual(corpus.alternate.exposureSeconds, 100)
        XCTAssertEqual(corpus.alternate.operatingSeconds, 100)
        XCTAssertEqual(corpus.alternate.qualifyingFailureStarts, 0)
        XCTAssertTrue(corpus.claims.degradedAndIntermittentHaveNoWeight)
        XCTAssertEqual(ServiceReliabilityClaimBoundaryV1.assignsNoDegradationWeight, true)

        let one = try NormalizedServiceIntervalV1(
            interval: C53AssetServiceReliabilityTestSupport.interval(0, 10),
            sourceEventIDs: [C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B1")]
        )
        let two = try NormalizedServiceIntervalV1(
            interval: C53AssetServiceReliabilityTestSupport.interval(10, 20),
            sourceEventIDs: [C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B2")]
        )
        let union = try ServiceReliabilityIntervalAlgebraV1.union([two, one])
        XCTAssertEqual(union.count, 1)
        XCTAssertEqual(try union[0].interval.durationMilliseconds, 20_000)
        let remainder = try ServiceReliabilityIntervalAlgebraV1.subtract(
            union,
            [try NormalizedServiceIntervalV1(
                interval: C53AssetServiceReliabilityTestSupport.interval(5, 15),
                sourceEventIDs: [C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B3")]
            )]
        )
        XCTAssertEqual(remainder.map(\.interval), [
            try C53AssetServiceReliabilityTestSupport.interval(0, 5),
            try C53AssetServiceReliabilityTestSupport.interval(15, 20),
        ])

        let subject = try C53AssetServiceReliabilityTestSupport.subject()
        let exposure = try C53AssetServiceReliabilityTestSupport.exposure(subject: subject)
        let degraded = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .degraded,
            origin: .unplanned,
            lower: 20,
            upper: 40,
            transitionID: nil,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B4"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B5")
        )
        let intermittent = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .intermittent,
            origin: .unplanned,
            lower: 40,
            upper: 60,
            transitionID: nil,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B6"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B7")
        )
        let projection = try ServiceReliabilityProjectionEngineV1.project(
            workspaceID: C53AssetServiceReliabilityTestSupport.workspace,
            subject: subject,
            observationWindow: try C53AssetServiceReliabilityTestSupport.interval(0, 100),
            asOf: C53AssetServiceReliabilityTestSupport.instant(100),
            exposures: [exposure],
            segments: [degraded, intermittent],
            repairs: [],
            restorations: []
        )
        XCTAssertEqual(projection.unplannedFullDowntimeMilliseconds, 0)
        XCTAssertEqual(projection.operatingExposureDurationMilliseconds, projection.exposureDurationMilliseconds)
        XCTAssertEqual(projection.mtbfQualification, .unavailable(.noQualifyingFailureStarts))
        XCTAssertTrue(corpus.alternate.unavailableReasons.contains("UNAVAILABLE_NO_QUALIFYING_FAILURE_STARTS"))

        let emptyProjection = try C53AssetServiceReliabilityTestSupport.project(
            subject: subject,
            exposures: [],
            segments: []
        )
        XCTAssertEqual(emptyProjection.availabilityQualification, .unavailable(.zeroQualifiedExposure))
        XCTAssertEqual(emptyProjection.mtbfQualification, .unavailable(.zeroQualifiedExposure))

        let incompleteProjection = try C53AssetServiceReliabilityTestSupport.project(
            subject: subject,
            exposures: [try C53AssetServiceReliabilityTestSupport.exposure(
                subject: subject,
                coverage: .incomplete,
                eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54BE"),
                mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54BF")
            )],
            segments: []
        )
        XCTAssertEqual(incompleteProjection.availabilityQualification, .unavailable(.incompleteCoverage))

        let unknownOrigin = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unknown,
            lower: 30,
            upper: 40,
            transitionID: nil,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C0"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C1")
        )
        let unknownOriginProjection = try C53AssetServiceReliabilityTestSupport.project(
            subject: subject,
            exposures: [exposure],
            segments: [unknownOrigin]
        )
        XCTAssertEqual(unknownOriginProjection.availabilityQualification, .unavailable(.unknownOrigin))

        let unknownImpact = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .unknown,
            origin: .unplanned,
            lower: 30,
            upper: 40,
            transitionID: nil,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C6"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C7")
        )
        let unknownImpactProjection = try C53AssetServiceReliabilityTestSupport.project(
            subject: subject,
            exposures: [exposure],
            segments: [unknownImpact]
        )
        XCTAssertEqual(unknownImpactProjection.availabilityQualification, .unavailable(.unknownImpact))

        let uncertainInterval = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unplanned,
            lower: 30,
            upper: 40,
            certainty: .estimated,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C8"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C9")
        )
        let uncertainProjection = try C53AssetServiceReliabilityTestSupport.project(
            subject: subject,
            exposures: [exposure],
            segments: [uncertainInterval]
        )
        XCTAssertEqual(uncertainProjection.availabilityQualification, .unavailable(.uncertainInterval))

        let fullDowntime = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unplanned,
            lower: 0,
            upper: 100,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54CA"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54CB")
        )
        let zeroOperatingProjection = try C53AssetServiceReliabilityTestSupport.project(
            subject: subject,
            exposures: [exposure],
            segments: [fullDowntime]
        )
        XCTAssertEqual(zeroOperatingProjection.operatingExposureDurationMilliseconds, 0)
        XCTAssertEqual(zeroOperatingProjection.mtbfQualification, .unavailable(.zeroQualifiedOperatingExposure))
        XCTAssertEqual(zeroOperatingProjection.mttrQualification, .unavailable(.noCompletedExactRepairs))

        let plannedOverlap = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .planned,
            lower: 30,
            upper: 40,
            transitionID: nil,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C2"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C3")
        )
        let plannedProjection = try C53AssetServiceReliabilityTestSupport.project(
            subject: subject,
            exposures: [exposure],
            segments: [plannedOverlap]
        )
        XCTAssertEqual(plannedProjection.availabilityQualification, .unavailable(.plannedOverlap))

        let unqualifiedStart = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unplanned,
            lower: 30,
            upper: 40,
            transitionID: nil,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C4"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54C5")
        )
        let unqualifiedStartProjection = try C53AssetServiceReliabilityTestSupport.project(
            subject: subject,
            exposures: [exposure],
            segments: [unqualifiedStart]
        )
        XCTAssertEqual(unqualifiedStartProjection.mtbfQualification, .unavailable(.missingTransitionIdentity))
    }

    func testV23P03C53H01HostileAndNonCanonicalReliabilityArtifactsRejectStrictly() throws {
        let corpus = try C53AssetServiceReliabilityTestSupport.fixture()
        XCTAssertTrue(corpus.hostileCases.contains("ABSOLUTE_LOCAL_PATH"))
        XCTAssertTrue(corpus.hostileCases.contains("UNICODE_BIDI_CONTROL"))
        XCTAssertTrue(corpus.hostileCases.contains("UNKNOWN_ENUM"))
        XCTAssertTrue(corpus.hostileCases.contains("MEDIA_OR_RESOURCE_BYTES"))
        XCTAssertTrue(corpus.hostileCases.contains("NON_CANONICAL_JSON"))
        XCTAssertTrue(corpus.hostileCases.contains("OPEN_INTERVAL"))
        XCTAssertTrue(corpus.hostileCases.contains("PLANNED_OVERLAP"))
        XCTAssertTrue(corpus.hostileCases.contains("UNCERTAIN_TIME_BOUNDS"))

        let subject = try C53AssetServiceReliabilityTestSupport.subject()
        let exposure = try C53AssetServiceReliabilityTestSupport.exposure(subject: subject)
        let canonical = try ServiceReliabilityCanonicalCodecV1.encode(exposure)
        XCTAssertEqual(
            try ServiceReliabilityCanonicalCodecV1.decode(QualifiedServiceExposureV1.self, from: canonical),
            exposure
        )
        let unknownKey = try C53AssetServiceReliabilityTestSupport.addJSONKey(
            canonical,
            key: "unrecognizedFutureField",
            value: true
        )
        XCTAssertThrowsError(
            try ServiceReliabilityCanonicalCodecV1.decode(QualifiedServiceExposureV1.self, from: unknownKey)
        )
        XCTAssertThrowsError(
            try ServiceReliabilityCanonicalCodecV1.decode(
                QualifiedServiceExposureV1.self,
                from: C53AssetServiceReliabilityTestSupport.addJSONKey(
                    canonical,
                    key: "coverage",
                    value: "NOT_A_COVERAGE"
                )
            )
        )
        XCTAssertThrowsError(
            try ServiceReliabilityCanonicalCodecV1.decode(
                QualifiedServiceExposureV1.self,
                from: C53AssetServiceReliabilityTestSupport.nonCanonical(canonical)
            )
        )
        XCTAssertThrowsError(
            try ServiceReliabilityCanonicalCodecV1.decode(
                QualifiedServiceExposureV1.self,
                from: C53AssetServiceReliabilityTestSupport.addJSONKey(
                    canonical,
                    key: "sourceNote",
                    value: "\u{202E}bounded\u{0001}"
                )
            )
        )

        let evidenceSegment = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unplanned,
            lower: 30,
            upper: 40,
            transitionID: nil,
            evidence: [try C53AssetServiceReliabilityTestSupport.contentReference()],
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54D0"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54D1")
        )
        let evidenceCanonical = try ServiceReliabilityCanonicalCodecV1.encode(evidenceSegment)
        XCTAssertThrowsError(
            try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceImpactSegmentV1.self,
                from: C53AssetServiceReliabilityTestSupport.replaceEvidenceJSONKey(
                    evidenceCanonical,
                    key: "contentID",
                    value: "/private/var/mobile/c53"
                )
            )
        )
        XCTAssertThrowsError(
            try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceImpactSegmentV1.self,
                from: C53AssetServiceReliabilityTestSupport.replaceEvidenceJSONKey(
                    evidenceCanonical,
                    key: "mediaType",
                    value: "application/octet-stream;resource=/tmp"
                )
            )
        )
        XCTAssertThrowsError(
            try C53AssetServiceReliabilityTestSupport.interval(30, 30)
        )

        let openDowntime = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unplanned,
            lower: nil,
            upper: nil,
            transitionID: nil,
            certainty: .unknown,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B8"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54B9")
        )
        let projection = try ServiceReliabilityProjectionEngineV1.project(
            workspaceID: C53AssetServiceReliabilityTestSupport.workspace,
            subject: subject,
            observationWindow: try C53AssetServiceReliabilityTestSupport.interval(0, 100),
            asOf: C53AssetServiceReliabilityTestSupport.instant(100),
            exposures: [exposure],
            segments: [openDowntime],
            repairs: [],
            restorations: []
        )
        XCTAssertEqual(projection.availabilityQualification, .unavailable(.openDowntime))
    }

    func testV23P03C53I01ExpectedRevisionAndCanonicalMutationBridgeRemainAtomic() async throws {
        let corpus = try C53AssetServiceReliabilityTestSupport.fixture()
        XCTAssertTrue(corpus.lifecycle.expectedRevision)
        XCTAssertTrue(corpus.lifecycle.oneWriter)
        XCTAssertTrue(corpus.lifecycle.durableReceipt)
        XCTAssertTrue(corpus.claims.telemetryAndPredictionAbsent)

        let subject = try C53AssetServiceReliabilityTestSupport.subject()
        let mutationID = try C53AssetServiceReliabilityTestSupport.mutation(
            "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54BA"
        )
        let exposure = try C53AssetServiceReliabilityTestSupport.exposure(
            subject: subject,
            mutationID: mutationID
        )
        let identity = try WorkspaceEntityIdentityV1(
            kind: .qualifiedServiceExposure,
            id: exposure.eventID
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: C53AssetServiceReliabilityTestSupport.workspace,
            generationID: C53AssetServiceReliabilityTestSupport.generationID,
            writerInstanceID: C53AssetServiceReliabilityTestSupport.writerInstanceID,
            workspaceRevision: 7,
            entityRevisions: [WorkspaceEntityRevisionV1(identity: identity, revision: 0)]
        )
        let bundle = try ServiceReliabilityAtomicBundleV1(
            workspaceID: C53AssetServiceReliabilityTestSupport.workspace,
            expectedRevision: expected,
            mutationID: mutationID,
            payloads: [.exposure(exposure)]
        )
        try bundle.validateForCanonicalWriter()
        XCTAssertEqual(bundle.expectedRevision, expected)
        XCTAssertEqual(try bundle.affectedIdentities, [identity])
        XCTAssertEqual(try bundle.concurrencyIdentities, [identity])
        XCTAssertEqual(try bundle.expectedRevision(for: identity), 0)

        let bundleBytes = try ServiceReliabilityCanonicalCodecV1.encode(bundle)
        XCTAssertEqual(
            try ServiceReliabilityCanonicalCodecV1.decode(ServiceReliabilityAtomicBundleV1.self, from: bundleBytes),
            bundle
        )
        XCTAssertThrowsError(
            try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceReliabilityAtomicBundleV1.self,
                from: C53AssetServiceReliabilityTestSupport.addJSONKey(
                    bundleBytes,
                    key: "unknownBundleField",
                    value: true
                )
            )
        )

        let request = try bundle.canonicalWorkspaceMutationRequest()
        XCTAssertEqual(request.mutationID, mutationID)
        XCTAssertEqual(request.expectedRevision, expected)
        guard case .applyServiceReliability(let bridgedBundle) = request.command else {
            return XCTFail("C53 bundle must bridge to the typed workspace command")
        }
        XCTAssertEqual(bridgedBundle, bundle)

        let plan = try AssetServiceReliabilityCommitPlanV1(
            expectedRevision: expected,
            mutationID: mutationID,
            payloads: [.exposure(exposure)]
        )
        try plan.validate()
        XCTAssertTrue(plan.zeroWrite)
        XCTAssertEqual(plan.bundle, bundle)
        XCTAssertFalse(C53AssetServiceReliabilityApplicationBoundaryV1.previewWritesWorkspace)
        XCTAssertTrue(C53AssetServiceReliabilityApplicationBoundaryV1.commitUsesExistingWorkspaceWriter)
        XCTAssertFalse(C53AssetServiceReliabilityApplicationBoundaryV1.createsSecondMutableTruth)

        let staleExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: C53AssetServiceReliabilityTestSupport.workspace,
            generationID: C53AssetServiceReliabilityTestSupport.generationID,
            writerInstanceID: C53AssetServiceReliabilityTestSupport.writerInstanceID,
            workspaceRevision: 7,
            entityRevisions: [WorkspaceEntityRevisionV1(identity: identity, revision: 1)]
        )
        XCTAssertThrowsError(
            try AssetServiceReliabilityCommitPlanV1(
                expectedRevision: staleExpected,
                mutationID: mutationID,
                payloads: [.exposure(exposure)]
            )
        ) { error in
            XCTAssertEqual(
                error as? AssetServiceReliabilityCoordinatorFailureV1,
                .invalidExpectedRevision
            )
        }

        let probe = C53LifecycleProbe()
        let lifecycle = AssetServiceReliabilityLifecycleAdapterV1(
            operations: AssetServiceReliabilityLifecycleOperationsV1(
                importAccepted: { bundles in
                    guard bundles.count == 1 else { return }
                    await probe.record("import")
                },
                restoreAccepted: { bundles in
                    guard bundles.count == 1 else { return }
                    await probe.record("restore")
                },
                replayAccepted: { bundles in
                    guard bundles.count == 1 else { return }
                    await probe.record("replay")
                },
                rebuildDerivedProjection: { bundles in
                    guard bundles.count == 1 else { return }
                    await probe.record("rebuild")
                },
                eraseWorkspace: { workspaceID in
                    guard workspaceID == C53AssetServiceReliabilityTestSupport.workspace else { return }
                    await probe.record("erase")
                }
            )
        )
        try await lifecycle.importAccepted([bundle])
        try await lifecycle.restoreAccepted([bundle])
        try await lifecycle.replayAccepted([bundle])
        try await lifecycle.rebuildDerivedProjection(from: [bundle])
        try await lifecycle.erase(workspaceID: C53AssetServiceReliabilityTestSupport.workspace)
        let lifecycleEvents = await probe.snapshot()
        XCTAssertEqual(lifecycleEvents, ["import", "restore", "replay", "rebuild", "erase"])
        XCTAssertFalse(C53AssetServiceReliabilityLifecycleBoundaryV1.createsSecondWriter)
        XCTAssertTrue(C53AssetServiceReliabilityLifecycleBoundaryV1.importRestoreReplayRevalidateCanonicalBundles)

        let writerReceipt = try ServiceReliabilityWriterReceiptV1(
            receiptID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54BD"),
            bundle: bundle,
            canonicalMutationReceiptSHA256: C53AssetServiceReliabilityTestSupport.digest("c"),
            committedAt: C53AssetServiceReliabilityTestSupport.fixedDate
        )
        let receiptBytes = try ServiceReliabilityCanonicalCodecV1.encode(writerReceipt)
        XCTAssertEqual(
            try ServiceReliabilityCanonicalCodecV1.decode(ServiceReliabilityWriterReceiptV1.self, from: receiptBytes),
            writerReceipt
        )
        XCTAssertThrowsError(
            try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceReliabilityWriterReceiptV1.self,
                from: C53AssetServiceReliabilityTestSupport.addJSONKey(
                    receiptBytes,
                    key: "unknownReceiptField",
                    value: "hostile"
                )
            )
        )
    }

    func testV23P03C53R01RecoveryRoundTripPreservesProjectionAndErasePrivacyBoundary() throws {
        let corpus = try C53AssetServiceReliabilityTestSupport.fixture()
        XCTAssertTrue(corpus.lifecycle.appendOnly)
        XCTAssertTrue(corpus.lifecycle.backupRestore)
        XCTAssertTrue(corpus.lifecycle.cloneForkInvalidation)
        XCTAssertTrue(corpus.lifecycle.journalReplay)
        XCTAssertTrue(corpus.lifecycle.projectionRebuild)
        XCTAssertTrue(corpus.lifecycle.erasePrivacy)
        XCTAssertTrue(corpus.lifecycle.compatibility)
        XCTAssertTrue(corpus.claims.restorationIsNotReleaseToService)
        XCTAssertTrue(corpus.claims.restorationIsNotSafetyOrCompliance)
        XCTAssertEqual(corpus.claims.mttrLabel, "MEAN_RECORDED_RESTORATION_INTERVAL")
        XCTAssertFalse(ServiceReliabilityClaimBoundaryV1.restorationImpliesSafety)
        XCTAssertFalse(ServiceReliabilityClaimBoundaryV1.restorationImpliesCompliance)
        XCTAssertTrue(ServiceReliabilityClaimBoundaryV1.restorationGrantsNoIndependentOperationalAuthority)

        let subject = try C53AssetServiceReliabilityTestSupport.subject()
        let exposure = try C53AssetServiceReliabilityTestSupport.exposure(subject: subject)
        let segment = try C53AssetServiceReliabilityTestSupport.segment(
            subject: subject,
            impact: .fullInterruption,
            origin: .unplanned,
            lower: 30,
            upper: 50,
            eventID: C53AssetServiceReliabilityTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54BB"),
            mutationID: try C53AssetServiceReliabilityTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A54BC")
        )
        let projection = try ServiceReliabilityProjectionEngineV1.project(
            workspaceID: C53AssetServiceReliabilityTestSupport.workspace,
            subject: subject,
            observationWindow: try C53AssetServiceReliabilityTestSupport.interval(0, 100),
            asOf: C53AssetServiceReliabilityTestSupport.instant(100),
            exposures: [exposure],
            segments: [segment],
            repairs: [try C53AssetServiceReliabilityTestSupport.repair(subject: subject)],
            restorations: [try C53AssetServiceReliabilityTestSupport.restoration(subject: subject, restoredAt: 50)]
        )
        let projectionBytes = try ServiceReliabilityCanonicalCodecV1.encode(projection)
        let restoredProjection = try ServiceReliabilityCanonicalCodecV1.decode(
            ReliabilityMetricInputProjectionV1.self,
            from: projectionBytes
        )
        XCTAssertEqual(restoredProjection, projection)
        try AssetServiceReliabilityPersistenceEnrollmentV1.validate()
        XCTAssertEqual(AssetServiceReliabilityPersistenceEnrollmentV1.durableModels.count, 7)
        XCTAssertFalse(AssetServiceReliabilityPersistenceEnrollmentV1.derivedProjectionIsPersistent)

        let row = try QualifiedServiceExposureRow(exposure)
        XCTAssertEqual(try row.value(), exposure)
        XCTAssertEqual(row.eventID, exposure.eventID)
        XCTAssertEqual(row.revision, exposure.revision)
        XCTAssertEqual(ServiceReliabilityIntervalAlgebraV1.policyID, "SERVICE_RELIABILITY_HALF_OPEN_UNION_SUBTRACT_V1")
    }
}
