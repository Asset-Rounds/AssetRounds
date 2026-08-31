import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C09OperationsMetricsCorpus: Decodable {
    struct Selector: Decodable {
        let id: String
        let selector: String
        let tier: String
    }

    struct MetricUnits: Decodable {
        let numerator: String
        let denominator: String
    }

    struct Golden: Decodable {
        let qualifiedExposureMilliseconds: UInt64
        let unplannedFullInterruptionMilliseconds: UInt64
        let operatingExposureMilliseconds: UInt64
        let mtbfComponentCount: UInt64
        let availabilitySampleCount: UInt64
        let expectedQualification: String
        let availabilityRatio: String
        let mtbfRatio: String
        let onlyC53CanonicalInputs: Bool
    }

    struct Alternate: Decodable {
        let timelineKinds: [String]
        let supplementalOwners: [String]
        let correctionRevisionCount: Int
        let recheckAndSupersessionPreserved: Bool
        let chronologyTieBreak: String
        let provenanceDigestRequired: Bool
    }

    struct Interruption: Decodable {
        let assetCount: Int
        let cancellationRequested: Bool
        let interruptionIsNonAcceptance: Bool
        let resumeUsesCanonicalInputs: Bool
        let corruptDerivedState: String
        let partialProjectionNotAccepted: Bool
    }

    struct Recovery: Decodable {
        let dropDerivedState: Bool
        let rebuildFromC53Inputs: Bool
        let canonicalRecordsPreserved: Bool
        let receiptsPreserved: Bool
        let reportsPreserved: Bool
        let exportsPreserved: Bool
        let privacyPreserved: Bool
    }

    struct Claims: Decodable {
        let onlyC53Inputs: Bool
        let noAppAgeInference: Bool
        let noAssetAgeInference: Bool
        let noWorkCountInference: Bool
        let noAbsentFailureUptime: Bool
        let noTelemetry: Bool
        let noCustomerLearningBridge: Bool
        let derivedOnly: Bool
        let canonicalTruthOwner: String
        let predecessorCyclesSubsumedByExactRevisionMonotonicity: Bool
    }

    struct StatusFlags: Decodable {
        let acceptance: Bool
        let activation: Bool
        let adoption: Bool
        let hosted: Bool
        let native: Bool
        let release: Bool
        let phase10PollingDuringParallelExecution: Bool
    }

    let schema: String
    let schemaVersion: Int
    let cardID: String
    let ordinal: Int
    let corpusID: String
    let testOnly: Bool
    let synthetic: Bool
    let immutable: Bool
    let containsCustomerData: Bool
    let containsSecrets: Bool
    let contracts: [String]
    let evidenceIDs: [String]
    let selectors: [Selector]
    let metricIDs: [String]
    let metricVersions: [Int]
    let metricUnits: [String: MetricUnits]
    let golden: Golden
    let alternate: Alternate
    let hostileCases: [String]
    let interruption: Interruption
    let recovery: Recovery
    let lifecycle: [String]
    let claims: Claims
    let statusFlags: StatusFlags
}

private struct C09ProjectionBasis: Codable {
    let schemaVersion: Int
    let definition: MetricDefinitionV1
    let workspaceID: WorkspaceID
    let subject: ServiceReliabilitySubjectV1
    let observationWindow: ServiceReliabilityClosedIntervalV1
    let asOf: ServiceReliabilityInstantV1
    let numeratorValue: UInt64
    let numeratorUnit: OperationsMetricUnitV1
    let denominatorValue: UInt64
    let denominatorUnit: OperationsMetricUnitV1
    let sampleCount: UInt64
    let qualification: ReliabilityMetricProjectionQualificationV1
    let unavailableReason: ServiceReliabilityUnavailableReasonV1?
    let includedSourceEventIDs: [UUID]
    let excludedSources: [ServiceReliabilityExcludedSourceV1]
    let qualifyingFailureStartEventIDs: [UUID]
    let inputProjectionSHA256: String
    let intervalUnionPolicySHA256: String
    let sourceClosureSHA256: String
    let availabilityNumeratorSHA256: String

    init(_ value: ReliabilityMetricProjectionV1, denominatorValue: UInt64) {
        schemaVersion = value.schemaVersion
        definition = value.definition
        workspaceID = value.workspaceID
        subject = value.subject
        observationWindow = value.observationWindow
        asOf = value.asOf
        numeratorValue = value.numeratorValue
        numeratorUnit = value.numeratorUnit
        self.denominatorValue = denominatorValue
        denominatorUnit = value.denominatorUnit
        sampleCount = value.sampleCount
        qualification = value.qualification
        unavailableReason = value.unavailableReason
        includedSourceEventIDs = value.includedSourceEventIDs
        excludedSources = value.excludedSources
        qualifyingFailureStartEventIDs = value.qualifyingFailureStartEventIDs
        inputProjectionSHA256 = value.inputProjectionSHA256
        intervalUnionPolicySHA256 = value.intervalUnionPolicySHA256
        sourceClosureSHA256 = value.sourceClosureSHA256
        availabilityNumeratorSHA256 = value.availabilityNumeratorSHA256
    }
}

private struct C09OpenJSONPayload: Decodable {
    let schema: String
    let ordering: String
    let dashboard: DashboardProjectionV1
    let timeline: AssetServiceHistoryTimelineV1
    let reportEnvelopes: [OperationsMetricsReportEnvelopeV1]
    let canonicalSourceClosureSHA256: String
}

private struct C09Clock: ApplicationClock {
    let value: Date

    func now() -> Date { value }
}

private struct C09IDSource: ApplicationIDSource {
    let value: UUID

    func makeID() -> UUID { value }
}

private struct C09FileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "c09/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class C09NoopWriterAdapter: WorkspaceWriterAdapterPortV1 {
    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }
}

@MainActor
private enum C09ApplicationTestFactory {
    static func coordinator(
        rebuildCoordinator: OperationsMetricsRebuildCoordinatorV1
    ) throws -> OperationsMetricsCoordinatorV1 {
        let workspace = C09OperationsMetricsTestSupport.workspace
        let generationID = C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5527")
        let writerInstanceID = C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5528")
        let replicaID = ReplicaID(rawValue: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5529"))
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: workspace, replicaID: replicaID)
        let initialRevision = try WorkspaceRevisionV1(
            workspaceID: workspace,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            revision: 0,
            entityRevisions: []
        )
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: initialRevision,
            clock: C09Clock(value: C09OperationsMetricsTestSupport.fixedDate),
            idSource: C09IDSource(value: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A552A")),
            fileAuthority: C09FileAuthority(),
            adapter: C09NoopWriterAdapter()
        )
        let lifecycle = AssetServiceReliabilityLifecycleAdapterV1(
            operations: AssetServiceReliabilityLifecycleOperationsV1(
                importAccepted: { _ in },
                restoreAccepted: { _ in },
                replayAccepted: { _ in },
                rebuildDerivedProjection: { _ in },
                eraseWorkspace: { _ in }
            )
        )
        let reliabilityCoordinator = AssetServiceReliabilityCoordinatorV1(writer: writer, lifecycle: lifecycle)
        return OperationsMetricsCoordinatorV1(
            reliabilityCoordinator: reliabilityCoordinator,
            rebuildCoordinator: rebuildCoordinator
        )
    }
}

private enum C09OperationsMetricsTestSupport {
    static let workspace = WorkspaceID(rawValue: UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5401")!)
    static let siteID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5402")!
    static let assetID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5403")!
    static let incidentID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5404")!
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

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
            method: try ObservationMethodV1(key: "C09_TYPED_TEST"),
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

    static func actor(
        responsibility: ResponsibilityKindV1 = .recordedBy,
        actorReferenceID: UUID = uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5407"),
        snapshotID: UUID = uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5408"),
        displayName: String = "C09 Typed Test Actor"
    ) throws -> ActorSnapshotV1 {
        let actor = try LocalActorReferenceV1(
            actorReferenceID: actorReferenceID,
            workspaceID: workspace,
            displayName: displayName
        )
        return try ActorSnapshotV1(
            snapshotID: snapshotID,
            workspaceID: workspace,
            actor: actor,
            responsibility: responsibility,
            displayNameAtTime: actor.displayName,
            capturedAt: fixedDate
        )
    }

    static func subject() throws -> ServiceReliabilitySubjectV1 {
        let package = try PackageReleaseIdentityV1(
            packageID: "com.field-evidence.c09.metrics",
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
            semanticID: "asset.kind.c09.metrics",
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
        eventID: UUID? = nil,
        exposureID: UUID? = nil,
        revision: UInt64 = 1,
        predecessor: ServiceReliabilityEventReferenceV1? = nil,
        recordedAtOffset: TimeInterval = 0,
        mutationID: MutationIDV1? = nil
    ) throws -> QualifiedServiceExposureV1 {
        let event = eventID ?? uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5413")
        let resolvedMutation = mutationID ?? (try self.mutation(
            revision == 1 ? "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5415" : "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541C"
        ))
        let exposureInterval = try interval(lower, upper)
        return try QualifiedServiceExposureV1(
            eventID: event,
            exposureID: exposureID ?? uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5414"),
            workspaceID: workspace,
            subject: subject,
            interval: exposureInterval,
            declaredCoverageWindow: exposureInterval,
            coverage: coverage,
            plannedNonserviceExclusions: plannedExclusions,
            source: .acceptedRecord,
            observationBasis: try observation(),
            timeBasis: try temporal(at: fixedDate.timeIntervalSince1970 + recordedAtOffset),
            sourceNote: "C09 deterministic fixture",
            recordedBy: try actor(),
            predecessor: predecessor,
            revision: revision,
            mutationID: resolvedMutation
        )
    }

    static func incident(
        eventID: UUID = uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5417"),
        revision: UInt64 = 1,
        predecessor: ServiceReliabilityEventReferenceV1? = nil,
        recordedAtOffset: TimeInterval = 10,
        subject: ServiceReliabilitySubjectV1
    ) throws -> AssetServiceIncidentV1 {
        try AssetServiceIncidentV1(
            eventID: eventID,
            incidentID: incidentID,
            workspaceID: workspace,
            subject: subject,
            continuation: .newOccurrence,
            observationBasis: try observation(),
            time: try temporal(at: fixedDate.timeIntervalSince1970 + recordedAtOffset),
            recordedBy: try actor(),
            predecessor: predecessor,
            revision: revision,
            mutationID: try mutation(revision == 1 ? "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5418" : "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5420")
        )
    }

    static func segment(
        subject: ServiceReliabilitySubjectV1,
        impact: ServiceImpactKindV1 = .fullInterruption,
        origin: ServiceImpactOriginV1 = .unplanned,
        lower: Int64 = 30,
        upper: Int64 = 60,
        transitionID: UUID? = uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5416"),
        certainty: ServiceTimeCertaintyV1 = .exact,
        eventID: UUID,
        segmentID: UUID? = nil,
        incidentID: UUID = C09OperationsMetricsTestSupport.incidentID,
        revision: UInt64 = 1,
        predecessor: ServiceReliabilityEventReferenceV1? = nil,
        recordedAtOffset: TimeInterval? = nil,
        mutationID: MutationIDV1
    ) throws -> ServiceImpactSegmentV1 {
        try ServiceImpactSegmentV1(
            eventID: eventID,
            segmentID: segmentID ?? eventID,
            incidentID: incidentID,
            workspaceID: workspace,
            subject: subject,
            impact: impact,
            origin: origin,
            interval: try interval(lower, upper),
            openedAt: instant(lower),
            certainty: certainty,
            transitionIntoImpactEventID: transitionID,
            observationBasis: try observation(),
            recordedTime: try temporal(at: fixedDate.timeIntervalSince1970 + (recordedAtOffset ?? TimeInterval(lower))),
            recordedBy: try actor(),
            predecessor: predecessor,
            revision: revision,
            mutationID: mutationID
        )
    }

    static func project(
        subject: ServiceReliabilitySubjectV1,
        exposures: [QualifiedServiceExposureV1],
        segments: [ServiceImpactSegmentV1]
    ) throws -> ReliabilityMetricInputProjectionV1 {
        try ServiceReliabilityProjectionEngineV1.project(
            workspaceID: workspace,
            subject: subject,
            observationWindow: try interval(0, 100),
            asOf: instant(100),
            exposures: exposures,
            segments: segments,
            repairs: [],
            restorations: []
        )
    }

    static func source(
        subject: ServiceReliabilitySubjectV1,
        observationLower: Int64 = 0,
        observationUpper: Int64 = 100,
        asOf: Int64 = 100,
        incidents: [AssetServiceIncidentV1] = [],
        exposures: [QualifiedServiceExposureV1] = [],
        segments: [ServiceImpactSegmentV1] = [],
        placementEvents: [AssetPoseEventV1] = [],
        supplementalEvents: [AssetServiceHistorySupplementalCanonicalEventV1] = []
    ) throws -> OperationsMetricsCanonicalSourceV1 {
        try OperationsMetricsCanonicalSourceV1(
            workspaceID: workspace,
            subject: subject,
            observationWindow: try interval(observationLower, observationUpper),
            asOf: instant(asOf),
            incidents: incidents,
            exposures: exposures,
            segments: segments,
            repairs: [],
            restorations: [],
            placementEvents: placementEvents,
            supplementalEvents: supplementalEvents
        )
    }

    static func c53MutationReceipt(
        exposure: QualifiedServiceExposureV1
    ) throws -> ServiceReliabilityMutationReceiptV1 {
        let payload = ServiceReliabilityMutationPayloadV1.exposure(exposure)
        let concurrencyIdentity = try payload.concurrencyIdentity
        let generationID = uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5542")
        let writerInstanceID = uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5543")
        let expectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: workspace,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: 0,
            entityRevisions: [try WorkspaceEntityRevisionV1(identity: concurrencyIdentity, revision: 0)]
        )
        let bundle = try ServiceReliabilityAtomicBundleV1(
            workspaceID: workspace,
            expectedRevision: expectedRevision,
            mutationID: exposure.mutationID,
            payloads: [payload]
        )
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspace,
            replicaID: ReplicaID(rawValue: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5544"))
        )
        let envelope = try MutationEnvelopeV1(
            request: bundle.canonicalWorkspaceMutationRequest(),
            identity: identity
        )
        let postImages = try bundle.mutationPostImages
        let resultingRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: workspace,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: 1,
            entityRevisions: try postImages.map {
                try WorkspaceEntityRevisionV1(identity: $0.identity, revision: $0.revision)
            }
        )
        let receipt = try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: workspace,
                replicaID: identity.replicaID,
                localSequence: 1
            ),
            envelope: envelope,
            resultingRevision: try MutationPortableExpectedRevisionV1(resultingRevision),
            postImages: postImages,
            committedAt: fixedDate
        )
        return try ServiceReliabilityMutationReceiptV1(bundle: bundle, mutationReceipt: receipt)
    }

    static func poseEvent(subject: ServiceReliabilitySubjectV1) throws -> AssetPoseEventV1 {
        let descriptor = try PoseAxisDescriptorV1(
            axisID: try PoseAxisID(rawValue: "c09.placement.axis"),
            localizedLabelKey: "c09.placement.axis",
            semanticRole: .assetForwardAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let occurredAt = fixedDate.addingTimeInterval(35)
        return try AssetPoseEventV1(
            eventID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5523"),
            workspaceID: workspace,
            assetID: subject.asset.subjectID,
            axisDescriptor: descriptor,
            placementEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5520")),
            placementEventID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5522"),
            locationPathSnapshot: try LocationPathSnapshotV1(siteID: siteID, siteDisplay: "C09 site", nodes: []),
            pose: try PlacementPoseV1(
                disposition: .notObserved,
                referenceFrame: .unknown,
                notObservedReason: .sourceUnavailable,
                descriptor: descriptor
            ),
            source: .manual,
            rootObservationEventID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5523"),
            rootObservedAt: occurredAt,
            predecessor: nil,
            revision: 1,
            mutationID: try mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5524"),
            recordedBy: try actor(
                responsibility: .observedBy,
                actorReferenceID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5525"),
                snapshotID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5526"),
                displayName: "C09 Placement Observer"
            ),
            occurredAt: occurredAt,
            recordedAt: occurredAt.addingTimeInterval(1)
        )
    }

    static func supplemental(
        kind: AssetServiceHistoryEventKindV1,
        owner: AssetServiceHistorySourceOwnerV1,
        eventID: UUID,
        revision: UInt64 = 1,
        occurredAtOffset: Int64,
        supersedes: AssetServiceHistorySupplementalCanonicalEventV1? = nil
    ) -> AssetServiceHistorySupplementalCanonicalEventV1 {
        .init(
            kind: kind,
            sourceOwner: owner,
            workspaceID: workspace,
            assetID: assetID,
            eventID: eventID,
            revision: revision,
            occurredAt: instant(Int64(fixedDate.timeIntervalSince1970) + occurredAtOffset),
            canonicalEventSHA256: digest("c"),
            supersedesEventID: supersedes?.eventID,
            supersedesEventSHA256: supersedes?.canonicalEventSHA256
        )
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    static func fixture() throws -> C09OperationsMetricsCorpus {
        let bundle = Bundle(for: V9_73OperationsMetricsTimelineTests.self)
        let url = bundle.url(
            forResource: "V22P04C09OperationsMetricsTimelineCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V22/Metrics"
        ) ?? bundle.url(
            forResource: "V22P04C09OperationsMetricsTimelineCorpusV1",
            withExtension: "json"
        )
        guard let url else { throw OperationsMetricsFailureV1.invalidProjection }
        return try decoder().decode(C09OperationsMetricsCorpus.self, from: Data(contentsOf: url))
    }
}

@MainActor
final class V9_73OperationsMetricsTimelineTests: XCTestCase {
    func testV23P04C09G01MetricDefinitionAndDashboardJSONReconciliationAreDeterministic() async throws {
        let corpus = try C09OperationsMetricsTestSupport.fixture()
        check(corpus, id: "G01", tier: "GOLDEN", selector: #function)
        XCTAssertEqual(corpus.schema, "V22P04C09OperationsMetricsTimelineCorpusV1")
        XCTAssertEqual(corpus.cardID, "V23-P04-C09")
        XCTAssertEqual(corpus.ordinal, 97)
        XCTAssertTrue(corpus.testOnly && corpus.synthetic && corpus.immutable)
        XCTAssertFalse(corpus.containsCustomerData || corpus.containsSecrets)
        XCTAssertEqual(corpus.metricIDs, OperationsMetricDefinitionIDV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.metricVersions, [MetricDefinitionV1.currentDefinitionVersion, MetricDefinitionV1.currentDefinitionVersion])
        XCTAssertEqual(corpus.metricUnits[corpus.metricIDs[0]]?.numerator, OperationsMetricUnitV1.milliseconds.rawValue)
        XCTAssertEqual(corpus.metricUnits[corpus.metricIDs[0]]?.denominator, OperationsMetricUnitV1.componentCount.rawValue)
        XCTAssertEqual(corpus.metricUnits[corpus.metricIDs[1]]?.numerator, OperationsMetricUnitV1.milliseconds.rawValue)
        XCTAssertEqual(corpus.metricUnits[corpus.metricIDs[1]]?.denominator, OperationsMetricUnitV1.qualifiedExposureMilliseconds.rawValue)

        try OperationsMetricsContractV1.validateRegistry()
        let subject = try C09OperationsMetricsTestSupport.subject()
        let exposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)]
        )
        let segment = try C09OperationsMetricsTestSupport.segment(
            subject: subject,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5419"),
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541A")
        )
        let input = try C09OperationsMetricsTestSupport.project(subject: subject, exposures: [exposure], segments: [segment])
        let source = try C09OperationsMetricsTestSupport.source(subject: subject, exposures: [exposure], segments: [segment])
        let rebuildCoordinator = OperationsMetricsRebuildCoordinatorV1()
        let applicationCoordinator = try C09ApplicationTestFactory.coordinator(rebuildCoordinator: rebuildCoordinator)
        let derived = try await applicationCoordinator.project(source: source)
        try derived.validate()
        let dashboard = derived.dashboard
        let repeated = try await applicationCoordinator.project(source: source)
        XCTAssertEqual(derived, repeated)
        let definitions = try OperationsMetricsContractV1.metricDefinitions()
        XCTAssertEqual(dashboard.metricProjections.map(\.definition), definitions)
        XCTAssertEqual(dashboard.metricProjections.map(\.definition.identifier), OperationsMetricDefinitionIDV1.allCases)
        XCTAssertEqual(derived.reportEnvelopes.map(\.metricDefinitionID), OperationsMetricDefinitionIDV1.allCases)
        XCTAssertEqual(derived.reportEnvelopes.map(\.metricDefinitionVersion), dashboard.metricProjections.map(\.definition.version))
        XCTAssertEqual(derived.reportEnvelopes.map(\.metricDefinitionSHA256), dashboard.metricProjections.map { $0.definition.definitionSHA256 })
        XCTAssertEqual(derived.reportEnvelopes.map(\.projection), dashboard.metricProjections)
        XCTAssertEqual(derived.reportProjection.sourceProjectionSHA256, derived.c53InputProjectionSHA256)
        XCTAssertEqual(dashboard.metricProjections.map(\.inputProjectionSHA256), [derived.c53InputProjectionSHA256, derived.c53InputProjectionSHA256])
        XCTAssertEqual(derived.canonicalSourceClosureSHA256, try source.canonicalSourceClosureSHA256())

        let openJSON = try C09OperationsMetricsTestSupport.decoder().decode(C09OpenJSONPayload.self, from: derived.openJSON)
        XCTAssertEqual(openJSON.schema, OperationsMetricsOpenJSONV1.schema)
        XCTAssertEqual(openJSON.ordering, OperationsMetricsOpenJSONV1.deterministicOrdering)
        XCTAssertEqual(openJSON.dashboard, dashboard)
        XCTAssertEqual(openJSON.timeline, derived.timeline)
        XCTAssertEqual(openJSON.reportEnvelopes, derived.reportEnvelopes)
        XCTAssertEqual(openJSON.canonicalSourceClosureSHA256, derived.canonicalSourceClosureSHA256)
        XCTAssertEqual(openJSON.reportEnvelopes.map(\.metricDefinitionID), dashboard.metricProjections.map { $0.definition.identifier })
        XCTAssertEqual(openJSON.reportEnvelopes.map(\.metricDefinitionVersion), dashboard.metricProjections.map { $0.definition.version })
        XCTAssertEqual(openJSON.reportEnvelopes.map(\.metricDefinitionSHA256), dashboard.metricProjections.map { $0.definition.definitionSHA256 })
        XCTAssertEqual(derived.openJSON, repeated.openJSON)

        let golden = corpus.golden
        XCTAssertEqual(input.exposureDurationMilliseconds, golden.qualifiedExposureMilliseconds)
        XCTAssertEqual(input.unplannedFullDowntimeMilliseconds, golden.unplannedFullInterruptionMilliseconds)
        XCTAssertEqual(input.operatingExposureDurationMilliseconds, golden.operatingExposureMilliseconds)
        XCTAssertEqual(UInt64(input.maximalDowntimeComponents.count), golden.mtbfComponentCount)
        XCTAssertEqual(dashboard.metricProjections[0].sampleCount, golden.mtbfComponentCount)
        XCTAssertEqual(dashboard.metricProjections[1].sampleCount, golden.availabilitySampleCount)
        XCTAssertEqual(dashboard.metricProjections.map(\.qualification.rawValue), [golden.expectedQualification, golden.expectedQualification])
        let expectedMTBF = try ServiceReliabilityRationalV1(numerator: 60_000, denominator: 1)
        let expectedAvailability = try ServiceReliabilityRationalV1(numerator: 2, denominator: 3)
        XCTAssertEqual(try dashboard.metricProjections[0].value, expectedMTBF)
        XCTAssertEqual(try dashboard.metricProjections[1].value, expectedAvailability)
        XCTAssertTrue(golden.onlyC53CanonicalInputs)
        XCTAssertEqual(dashboard.metricProjections[0].availabilityNumeratorSHA256, dashboard.metricProjections[1].availabilityNumeratorSHA256)

        let canonical = try WorkspaceMutationCanonicalV1.data(dashboard)
        XCTAssertEqual(canonical, try WorkspaceMutationCanonicalV1.data(repeated))
        let decoded = try C09OperationsMetricsTestSupport.decoder().decode(DashboardProjectionV1.self, from: canonical)
        try decoded.validate()
        XCTAssertEqual(decoded, dashboard)
        XCTAssertEqual(OperationsMetricsOpenJSONV1.schema, "OPERATIONS_METRICS_OPEN_JSON_V1")
        XCTAssertEqual(OperationsMetricsOpenJSONV1.deterministicOrdering, "METRIC_DEFINITION_REGISTRY_ORDER")
        XCTAssertTrue(OperationsMetricsOpenJSONV1.definitionAndDashboardAgreementRequired)
    }

    func testV23P04C09A01AssetTimelineOrderAndProvenanceRemainExactAcrossCorrectiveLifecycle() throws {
        let corpus = try C09OperationsMetricsTestSupport.fixture()
        check(corpus, id: "A01", tier: "ALTERNATE", selector: #function)
        XCTAssertEqual(corpus.alternate.timelineKinds, [
            AssetServiceHistoryEventKindV1.incident.rawValue,
            AssetServiceHistoryEventKindV1.impactSegment.rawValue,
            AssetServiceHistoryEventKindV1.qualifiedExposure.rawValue,
            AssetServiceHistoryEventKindV1.inspection.rawValue,
            AssetServiceHistoryEventKindV1.finding.rawValue,
            AssetServiceHistoryEventKindV1.correctiveWork.rawValue,
            AssetServiceHistoryEventKindV1.recheck.rawValue,
            AssetServiceHistoryEventKindV1.report.rawValue,
            AssetServiceHistoryEventKindV1.evidenceAssociation.rawValue,
            AssetServiceHistoryEventKindV1.explicitAssetChange.rawValue,
            AssetServiceHistoryEventKindV1.placementChange.rawValue
        ])
        XCTAssertEqual(corpus.alternate.supplementalOwners, [
            AssetServiceHistorySourceOwnerV1.inspection.rawValue,
            AssetServiceHistorySourceOwnerV1.finding.rawValue,
            AssetServiceHistorySourceOwnerV1.correctiveWork.rawValue,
            AssetServiceHistorySourceOwnerV1.recheck.rawValue,
            AssetServiceHistorySourceOwnerV1.report.rawValue,
            AssetServiceHistorySourceOwnerV1.evidenceAssociation.rawValue,
            AssetServiceHistorySourceOwnerV1.explicitAssetChange.rawValue
        ])
        XCTAssertEqual(corpus.alternate.correctionRevisionCount, 2)
        XCTAssertTrue(corpus.alternate.recheckAndSupersessionPreserved)
        XCTAssertEqual(corpus.alternate.chronologyTieBreak, "recordedAt,kind,eventID")
        XCTAssertTrue(corpus.alternate.provenanceDigestRequired)

        let subject = try C09OperationsMetricsTestSupport.subject()
        let firstExposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)]
        )
        let correctedExposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)],
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541B"),
            revision: 2,
            predecessor: firstExposure.reference,
            recordedAtOffset: 120,
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541C")
        )
        try correctedExposure.validateSuccessor(of: firstExposure)
        let incident = try C09OperationsMetricsTestSupport.incident(subject: subject)
        let segment = try C09OperationsMetricsTestSupport.segment(
            subject: subject,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5419"),
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541A")
        )
        let placement = try C09OperationsMetricsTestSupport.poseEvent(subject: subject)
        let inspection = C09OperationsMetricsTestSupport.supplemental(
            kind: .inspection,
            owner: .inspection,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5530"),
            occurredAtOffset: 40
        )
        let finding = C09OperationsMetricsTestSupport.supplemental(
            kind: .finding,
            owner: .finding,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5531"),
            occurredAtOffset: 50
        )
        let correctiveWork = C09OperationsMetricsTestSupport.supplemental(
            kind: .correctiveWork,
            owner: .correctiveWork,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5532"),
            occurredAtOffset: 60
        )
        let recheck = C09OperationsMetricsTestSupport.supplemental(
            kind: .recheck,
            owner: .recheck,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5533"),
            occurredAtOffset: 70
        )
        let correctedRecheck = C09OperationsMetricsTestSupport.supplemental(
            kind: .recheck,
            owner: .recheck,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5534"),
            revision: 2,
            occurredAtOffset: 80,
            supersedes: recheck
        )
        let report = C09OperationsMetricsTestSupport.supplemental(
            kind: .report,
            owner: .report,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5535"),
            occurredAtOffset: 90
        )
        let evidenceAssociation = C09OperationsMetricsTestSupport.supplemental(
            kind: .evidenceAssociation,
            owner: .evidenceAssociation,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5536"),
            occurredAtOffset: 100
        )
        let explicitAssetChange = C09OperationsMetricsTestSupport.supplemental(
            kind: .explicitAssetChange,
            owner: .explicitAssetChange,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5537"),
            occurredAtOffset: 110
        )
        let supplementalEvents = [inspection, finding, correctiveWork, recheck, correctedRecheck, report, evidenceAssociation, explicitAssetChange]
        let timeline = try AssetServiceHistoryTimelineV1(
            workspaceID: C09OperationsMetricsTestSupport.workspace,
            subject: subject,
            incidents: [incident],
            impactSegments: [segment],
            exposures: [firstExposure, correctedExposure],
            placementEvents: [placement],
            supplementalEvents: supplementalEvents
        )
        try timeline.validate()
        XCTAssertEqual(timeline.entries.map(\.eventID), [
            firstExposure.eventID,
            incident.eventID,
            segment.eventID,
            placement.eventID,
            inspection.eventID,
            finding.eventID,
            correctiveWork.eventID,
            recheck.eventID,
            correctedRecheck.eventID,
            report.eventID,
            evidenceAssociation.eventID,
            explicitAssetChange.eventID,
            correctedExposure.eventID
        ])
        XCTAssertEqual(timeline.entries.map(\.sourceRevision), [1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2])
        XCTAssertEqual(timeline.entries.map(\.kind.rawValue), [
            AssetServiceHistoryEventKindV1.qualifiedExposure.rawValue,
            AssetServiceHistoryEventKindV1.incident.rawValue,
            AssetServiceHistoryEventKindV1.impactSegment.rawValue,
            AssetServiceHistoryEventKindV1.placementChange.rawValue,
            AssetServiceHistoryEventKindV1.inspection.rawValue,
            AssetServiceHistoryEventKindV1.finding.rawValue,
            AssetServiceHistoryEventKindV1.correctiveWork.rawValue,
            AssetServiceHistoryEventKindV1.recheck.rawValue,
            AssetServiceHistoryEventKindV1.recheck.rawValue,
            AssetServiceHistoryEventKindV1.report.rawValue,
            AssetServiceHistoryEventKindV1.evidenceAssociation.rawValue,
            AssetServiceHistoryEventKindV1.explicitAssetChange.rawValue,
            AssetServiceHistoryEventKindV1.qualifiedExposure.rawValue
        ])

        let provenance: [UUID: String] = [
            firstExposure.eventID: firstExposure.eventSHA256,
            correctedExposure.eventID: correctedExposure.eventSHA256,
            incident.eventID: incident.eventSHA256,
            segment.eventID: segment.eventSHA256,
            placement.eventID: placement.eventSHA256
        ]
        for entry in timeline.entries {
            let expectedDigest = provenance[entry.eventID] ?? supplementalEvents.first(where: { $0.eventID == entry.eventID })?.canonicalEventSHA256
            XCTAssertEqual(entry.canonicalEventSHA256, expectedDigest)
            XCTAssertEqual(entry.sourceOwner, expectedOwner(for: entry.kind))
        }
        XCTAssertEqual(correctedExposure.predecessor, firstExposure.reference)
        XCTAssertEqual(correctedExposure.revision, 2)
        XCTAssertEqual(correctedRecheck.supersedesEventID, recheck.eventID)
        XCTAssertEqual(correctedRecheck.supersedesEventSHA256, recheck.canonicalEventSHA256)
        let correctedEntry = try XCTUnwrap(timeline.entries.first(where: { $0.eventID == correctedRecheck.eventID }))
        XCTAssertEqual(correctedEntry.supersedesEventID, recheck.eventID)
        XCTAssertEqual(correctedEntry.supersedesEventSHA256, recheck.canonicalEventSHA256)
        let repeated = try AssetServiceHistoryTimelineV1(
            workspaceID: C09OperationsMetricsTestSupport.workspace,
            subject: subject,
            incidents: [incident],
            impactSegments: [segment],
            exposures: [firstExposure, correctedExposure],
            placementEvents: [placement],
            supplementalEvents: supplementalEvents
        )
        XCTAssertEqual(repeated, timeline)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(repeated), try WorkspaceMutationCanonicalV1.data(timeline))
    }

    func testV23P04C09H01MetricDefinitionOutputDisagreementDoubleCountAndOwnerBridgeFailClosed() async throws {
        let corpus = try C09OperationsMetricsTestSupport.fixture()
        check(corpus, id: "H01", tier: "HOSTILE", selector: #function)
        XCTAssertTrue(corpus.hostileCases.contains("DEFINITION_OUTPUT_DISAGREEMENT"))
        XCTAssertTrue(corpus.hostileCases.contains("REPLAY_DOUBLE_COUNT"))
        XCTAssertTrue(corpus.hostileCases.contains("UNKNOWN_METRIC_VERSION"))
        XCTAssertTrue(corpus.hostileCases.contains("CORRUPT_CANONICAL_EVENT"))
        XCTAssertTrue(corpus.hostileCases.contains("ARITHMETIC_OVERFLOW"))
        XCTAssertTrue(corpus.hostileCases.contains("CUSTOMER_LEARNING_OWNER_BRIDGE"))
        XCTAssertTrue(corpus.hostileCases.contains("MISSING_PREDECESSOR"))
        XCTAssertTrue(corpus.hostileCases.contains("WRONG_PREDECESSOR_DIGEST"))
        XCTAssertTrue(corpus.hostileCases.contains("OWNER_KIND_MISMATCH"))
        XCTAssertTrue(corpus.hostileCases.contains("NON_SUCCESSOR_REVISION"))
        XCTAssertTrue(corpus.hostileCases.contains("FORKED_PREDECESSOR"))
        XCTAssertTrue(corpus.hostileCases.contains("MULTI_NODE_CYCLE_SUBSUMED_BY_EXACT_REVISION_MONOTONICITY"))
        XCTAssertTrue(corpus.claims.predecessorCyclesSubsumedByExactRevisionMonotonicity)
        XCTAssertTrue(corpus.lifecycle.contains("EXACT_REVISION_MONOTONICITY"))
        XCTAssertTrue(corpus.hostileCases.contains("CANONICAL_CLOSURE_INCIDENT_STALE"))
        XCTAssertTrue(corpus.hostileCases.contains("CANONICAL_CLOSURE_C37_PLACEMENT_STALE"))
        XCTAssertTrue(corpus.hostileCases.contains("CANONICAL_CLOSURE_SUPPLEMENTAL_STALE"))

        XCTAssertThrowsError(try MetricDefinitionV1(
            identifier: .qualifiedRecordedUnplannedMTBF,
            numeratorUnit: .milliseconds,
            denominatorUnit: .qualifiedExposureMilliseconds
        )) { error in
            XCTAssertEqual(error as? OperationsMetricsFailureV1, .invalidDefinition)
        }

        let subject = try C09OperationsMetricsTestSupport.subject()
        let exposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)]
        )
        let segment = try C09OperationsMetricsTestSupport.segment(
            subject: subject,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5419"),
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541A")
        )
        let input = try C09OperationsMetricsTestSupport.project(subject: subject, exposures: [exposure], segments: [segment])
        let dashboard = try DashboardProjectionV1(input: input)
        let metric = dashboard.metricProjections[0]
        var forgedJSON = try JSONSerialization.jsonObject(with: WorkspaceMutationCanonicalV1.data(metric)) as! [String: Any]
        let forgedDenominator = metric.denominatorValue + 1
        forgedJSON["denominatorValue"] = forgedDenominator
        forgedJSON["projectionSHA256"] = try WorkspaceMutationCanonicalV1.sha256(C09ProjectionBasis(metric, denominatorValue: forgedDenominator))
        let forgedData = try JSONSerialization.data(withJSONObject: forgedJSON, options: [.sortedKeys])
        let forged = try C09OperationsMetricsTestSupport.decoder().decode(ReliabilityMetricProjectionV1.self, from: forgedData)
        XCTAssertThrowsError(try forged.validate()) { error in
            XCTAssertEqual(error as? OperationsMetricsFailureV1, .definitionOutputDisagreement)
        }

        let correctedSegment = try C09OperationsMetricsTestSupport.segment(
            subject: subject,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541D"),
            segmentID: segment.segmentID,
            revision: 2,
            predecessor: segment.reference,
            recordedAtOffset: 90,
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541E")
        )
        try correctedSegment.validateSuccessor(of: segment)
        let correctedInput = try C09OperationsMetricsTestSupport.project(
            subject: subject,
            exposures: [exposure],
            segments: [segment, correctedSegment]
        )
        XCTAssertEqual(correctedInput.unplannedFullDowntimeMilliseconds, input.unplannedFullDowntimeMilliseconds)
        XCTAssertEqual(correctedInput.maximalDowntimeComponents.count, 1)
        XCTAssertEqual(correctedInput.qualifyingFailureStartEventIDs.count, 1)
        XCTAssertFalse(correctedInput.includedSourceEventIDs.contains(segment.eventID))
        XCTAssertTrue(correctedInput.includedSourceEventIDs.contains(correctedSegment.eventID))

        let incident = try C09OperationsMetricsTestSupport.incident(subject: subject)
        XCTAssertThrowsError(try AssetServiceHistoryTimelineV1(
            workspaceID: C09OperationsMetricsTestSupport.workspace,
            subject: subject,
            incidents: [incident, incident],
            impactSegments: [],
            exposures: []
        )) { error in
            XCTAssertEqual(error as? OperationsMetricsFailureV1, .duplicateSourceEvent)
        }
        let unknownSegment = try C09OperationsMetricsTestSupport.segment(
            subject: subject,
            impact: .unknown,
            transitionID: nil,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541F"),
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5421")
        )
        let unknownInput = try C09OperationsMetricsTestSupport.project(subject: subject, exposures: [exposure], segments: [unknownSegment])
        XCTAssertEqual(unknownInput.availabilityQualification, .unavailable(.unknownImpact))
        let unknownDashboard = try DashboardProjectionV1(input: unknownInput)
        XCTAssertTrue(unknownDashboard.metricProjections.allSatisfy { $0.qualification == .unavailable })

        let source = try C09OperationsMetricsTestSupport.source(
            subject: subject,
            incidents: [incident],
            exposures: [exposure],
            segments: [segment]
        )
        let rebuildCoordinator = OperationsMetricsRebuildCoordinatorV1()
        let applicationCoordinator = try C09ApplicationTestFactory.coordinator(rebuildCoordinator: rebuildCoordinator)
        let baselineDerived = try await applicationCoordinator.project(source: source)
        let baselineClosure = try source.canonicalSourceClosureSHA256()
        XCTAssertEqual(baselineDerived.canonicalSourceClosureSHA256, baselineClosure)
        XCTAssertEqual(baselineDerived.c53InputProjectionSHA256, input.projectionSHA256)

        let changedIncident = try C09OperationsMetricsTestSupport.incident(
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5550"),
            recordedAtOffset: 11,
            subject: subject
        )
        let placement = try C09OperationsMetricsTestSupport.poseEvent(subject: subject)
        let supplemental = C09OperationsMetricsTestSupport.supplemental(
            kind: .inspection,
            owner: .inspection,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5551"),
            occurredAtOffset: 40
        )
        let closureVariants = [
            try C09OperationsMetricsTestSupport.source(
                subject: subject,
                incidents: [changedIncident],
                exposures: [exposure],
                segments: [segment]
            ),
            try C09OperationsMetricsTestSupport.source(
                subject: subject,
                incidents: [incident],
                exposures: [exposure],
                segments: [segment],
                placementEvents: [placement]
            ),
            try C09OperationsMetricsTestSupport.source(
                subject: subject,
                incidents: [incident],
                exposures: [exposure],
                segments: [segment],
                supplementalEvents: [supplemental]
            )
        ]
        let continuationSource = try C09OperationsMetricsTestSupport.source(
            subject: subject,
            observationLower: 1,
            observationUpper: 100,
            asOf: 100,
            exposures: [exposure],
            segments: [segment]
        )
        let firstBatch = try await rebuildCoordinator.rebuild(
            sources: [source, continuationSource],
            maximumOutputs: 1
        )
        let continuation = try XCTUnwrap(firstBatch.continuation)
        for variant in closureVariants {
            let variantClosure = try variant.canonicalSourceClosureSHA256()
            XCTAssertNotEqual(variantClosure, baselineClosure)
            let variantDerived = try await rebuildCoordinator.rebuild(sources: [variant])
            let projection = try XCTUnwrap(variantDerived.projections.first)
            XCTAssertEqual(projection.canonicalSourceClosureSHA256, variantClosure)
            XCTAssertEqual(projection.c53InputProjectionSHA256, baselineDerived.c53InputProjectionSHA256)
            do {
                _ = try await applicationCoordinator.project(
                    source: variant,
                    expectedSourceClosureSHA256: baselineClosure
                )
                XCTFail("A stale full canonical closure must fail reconciliation")
            } catch let error as OperationsMetricsCoordinatorFailureV1 {
                XCTAssertEqual(error, .sourceRevisionMismatch)
            }
            do {
                _ = try await rebuildCoordinator.rebuild(
                    sources: [variant, continuationSource],
                    continuation: continuation,
                    maximumOutputs: 1
                )
                XCTFail("A continuation with a stale full canonical closure must fail closed")
            } catch let error as OperationsMetricsRebuildFailureV1 {
                XCTAssertEqual(error, .staleContinuation)
            }
            do {
                _ = try await rebuildCoordinator.validateOrDiscard(
                    baselineDerived,
                    source: variant
                )
                XCTFail("A stale derived projection must be discarded")
            } catch let error as OperationsMetricsRebuildFailureV1 {
                XCTAssertEqual(error, .corruptDerivedProjection)
            }
        }

        let derived = try await rebuildCoordinator.rebuild(sources: [source])
        let canonicalDerived = try XCTUnwrap(derived.projections.first)
        var nonCanonicalOpenJSON = canonicalDerived.openJSON
        nonCanonicalOpenJSON.append(contentsOf: Data(" ".utf8))
        let forgedDerived = OperationsMetricsDerivedProjectionV1(
            dashboard: canonicalDerived.dashboard,
            timeline: canonicalDerived.timeline,
            reportProjection: canonicalDerived.reportProjection,
            reportEnvelopes: canonicalDerived.reportEnvelopes,
            openJSON: nonCanonicalOpenJSON,
            canonicalSourceClosureSHA256: canonicalDerived.canonicalSourceClosureSHA256
        )
        XCTAssertThrowsError(try forgedDerived.validate()) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .nonCanonicalEncoding)
        }

        XCTAssertThrowsError(try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            revision: 2
        )) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .invalidHistory)
        }

        let firstCycleCandidate = try C09OperationsMetricsTestSupport.exposure(subject: subject)
        let secondCycleCandidate = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5545"),
            exposureID: firstCycleCandidate.exposureID,
            revision: 2,
            predecessor: firstCycleCandidate.reference,
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5546")
        )
        try secondCycleCandidate.validateSuccessor(of: firstCycleCandidate)
        XCTAssertThrowsError(try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            eventID: firstCycleCandidate.eventID,
            exposureID: firstCycleCandidate.exposureID,
            revision: 1,
            predecessor: secondCycleCandidate.reference,
            mutationID: firstCycleCandidate.mutationID
        )) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .invalidHistory)
        }
        let wrongPredecessor = ServiceReliabilityEventReferenceV1(
            eventID: exposure.eventID,
            revision: exposure.revision,
            eventSHA256: C09OperationsMetricsTestSupport.digest("b")
        )
        let wrongPredecessorExposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)],
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5540"),
            revision: 2,
            predecessor: wrongPredecessor,
            recordedAtOffset: 90,
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5541")
        )
        XCTAssertThrowsError(try wrongPredecessorExposure.validateSuccessor(of: exposure)) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .invalidHistory)
        }
        let nonSuccessorRevision = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)],
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5542"),
            revision: 3,
            predecessor: exposure.reference,
            recordedAtOffset: 90,
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5543")
        )
        XCTAssertThrowsError(try nonSuccessorRevision.validateSuccessor(of: exposure)) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .invalidHistory)
        }
        let forkedExposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)],
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5544"),
            revision: 2,
            predecessor: exposure.reference,
            recordedAtOffset: 91,
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5545")
        )
        try forkedExposure.validateSuccessor(of: exposure)
        let secondFork = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)],
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5549"),
            revision: 2,
            predecessor: exposure.reference,
            recordedAtOffset: 92,
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A554A")
        )
        try secondFork.validateSuccessor(of: exposure)
        XCTAssertThrowsError(try C09OperationsMetricsTestSupport.project(
            subject: subject,
            exposures: [exposure, wrongPredecessorExposure],
            segments: []
        )) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .invalidHistory)
        }
        XCTAssertThrowsError(try C09OperationsMetricsTestSupport.project(
            subject: subject,
            exposures: [exposure, forkedExposure, secondFork],
            segments: []
        )) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .invalidHistory)
        }
        let mismatchedOwner = C09OperationsMetricsTestSupport.supplemental(
            kind: .inspection,
            owner: .finding,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5548"),
            occurredAtOffset: 40
        )
        XCTAssertThrowsError(try mismatchedOwner.validate()) { error in
            XCTAssertEqual(error as? OperationsMetricsFailureV1, .invalidProjection)
        }

        var unknownVersionJSON = try JSONSerialization.jsonObject(with: WorkspaceMutationCanonicalV1.data(metric.definition)) as! [String: Any]
        unknownVersionJSON["version"] = 2
        let unknownVersion = try C09OperationsMetricsTestSupport.decoder().decode(
            MetricDefinitionV1.self,
            from: JSONSerialization.data(withJSONObject: unknownVersionJSON, options: [.sortedKeys])
        )
        XCTAssertThrowsError(try unknownVersion.validate()) { error in
            XCTAssertEqual(error as? OperationsMetricsFailureV1, .invalidDefinition)
        }

        var corruptEventJSON = try JSONSerialization.jsonObject(with: ServiceReliabilityCanonicalCodecV1.encode(exposure)) as! [String: Any]
        corruptEventJSON["eventSHA256"] = C09OperationsMetricsTestSupport.digest("b")
        let corruptEventData = try JSONSerialization.data(withJSONObject: corruptEventJSON, options: [.sortedKeys])
        XCTAssertThrowsError(try ServiceReliabilityCanonicalCodecV1.decode(QualifiedServiceExposureV1.self, from: corruptEventData)) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .invalidHistory)
        }
        XCTAssertThrowsError(try ServiceReliabilityLimitsV1.add(UInt64.max, 1)) { error in
            XCTAssertEqual(error as? ServiceReliabilityFailureV1, .arithmeticOverflow)
        }
        XCTAssertTrue(OperationsMetricsClaimBoundaryV1.derivesOnlyFromC53CanonicalInputs)
        XCTAssertFalse(OperationsMetricsClaimBoundaryV1.infersExposureFromAppAge)
        XCTAssertFalse(OperationsMetricsClaimBoundaryV1.infersExposureFromAssetAge)
        XCTAssertFalse(OperationsMetricsClaimBoundaryV1.infersExposureFromWorkCounts)
        XCTAssertFalse(OperationsMetricsClaimBoundaryV1.infersUptimeFromAbsentFailures)
        XCTAssertFalse(OperationsMetricsClaimBoundaryV1.bridgesCustomerLearningMetricDefinition)
        XCTAssertFalse(OperationsMetricsClaimBoundaryV1.writesCanonicalTruth)
        XCTAssertFalse(OperationsMetricsClaimBoundaryV1.grantsOptimisticCompletionClaim)
        XCTAssertEqual(OperationsMetricsContractV1.canonicalTruthOwner, corpus.claims.canonicalTruthOwner)
        try OperationsMetricsClaimBoundaryV1.validate()
    }

    func testV23P04C09I01InterruptedScaleRebuildCancellationAndDerivedIndexCorruptionRemainDeterministic() async throws {
        let corpus = try C09OperationsMetricsTestSupport.fixture()
        check(corpus, id: "I01", tier: "INTERRUPTION", selector: #function)
        let interruption = corpus.interruption
        XCTAssertEqual(interruption.assetCount, ServiceReliabilityLimitsV1.maximumIntervals)
        XCTAssertTrue(interruption.cancellationRequested)
        XCTAssertTrue(interruption.interruptionIsNonAcceptance)
        XCTAssertTrue(interruption.resumeUsesCanonicalInputs)
        XCTAssertTrue(interruption.partialProjectionNotAccepted)
        XCTAssertEqual(interruption.corruptDerivedState, OperationsMetricsDerivedLifecycleV1.corruptState)

        let subject = try C09OperationsMetricsTestSupport.subject()
        let exposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)]
        )
        let segment = try C09OperationsMetricsTestSupport.segment(
            subject: subject,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5419"),
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541A")
        )
        let canonicalSource = try C09OperationsMetricsTestSupport.source(
            subject: subject,
            exposures: [exposure],
            segments: [segment]
        )
        let scaleSources = try (0..<interruption.assetCount).map { index in
            try C09OperationsMetricsTestSupport.source(
                subject: subject,
                observationLower: Int64(index),
                observationUpper: Int64(index + 1),
                asOf: Int64(index + 1)
            )
        }
        XCTAssertEqual(scaleSources.count, OperationsMetricsCanonicalSourceV1.maximumAssetsPerRebuild)
        let rebuildCoordinator = OperationsMetricsRebuildCoordinatorV1()
        let cancellationTask = Task {
            try await rebuildCoordinator.rebuild(sources: scaleSources, maximumOutputs: 1)
        }
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            XCTFail("Cancelled 10,000-source rebuild must not be accepted")
        } catch is CancellationError {
            // Cancellation is a non-accepting interruption; resume starts from canonical input.
        }

        let secondSource = try C09OperationsMetricsTestSupport.source(
            subject: subject,
            observationLower: 1,
            observationUpper: 100,
            asOf: 100,
            exposures: [exposure],
            segments: [segment]
        )
        let firstBatch = try await rebuildCoordinator.rebuild(
            sources: [canonicalSource, secondSource],
            maximumOutputs: 1
        )
        let continuation = try XCTUnwrap(firstBatch.continuation)
        let resumedBatch = try await rebuildCoordinator.rebuild(
            sources: [canonicalSource, secondSource],
            continuation: continuation,
            maximumOutputs: 1
        )
        let complete = try await rebuildCoordinator.rebuild(sources: [canonicalSource, secondSource])
        XCTAssertNil(resumedBatch.continuation)
        XCTAssertEqual(firstBatch.projections + resumedBatch.projections, complete.projections)
        XCTAssertTrue(corpus.lifecycle.contains("CANCELLATION_RESUME"))

        let mutatedExposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)],
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5540"),
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5541")
        )
        let mutatedSource = try C09OperationsMetricsTestSupport.source(
            subject: subject,
            exposures: [mutatedExposure],
            segments: [segment]
        )
        do {
            _ = try await rebuildCoordinator.rebuild(
                sources: [mutatedSource, secondSource],
                continuation: continuation,
                maximumOutputs: 1
            )
            XCTFail("A continuation for a different canonical source set must fail closed")
        } catch let error as OperationsMetricsRebuildFailureV1 {
            XCTAssertEqual(error, .staleContinuation)
        }

        let canonicalDerived = try XCTUnwrap(complete.projections.first)
        let corruptDerived = OperationsMetricsDerivedProjectionV1(
            dashboard: canonicalDerived.dashboard,
            timeline: canonicalDerived.timeline,
            reportProjection: canonicalDerived.reportProjection,
            reportEnvelopes: canonicalDerived.reportEnvelopes,
            openJSON: Data("corrupt-derived-index".utf8),
            canonicalSourceClosureSHA256: canonicalDerived.canonicalSourceClosureSHA256
        )
        do {
            _ = try await rebuildCoordinator.validateOrDiscard(corruptDerived)
            XCTFail("Corrupt derived state must be discarded and fail closed")
        } catch let error as OperationsMetricsRebuildFailureV1 {
            XCTAssertEqual(error, .corruptDerivedProjection)
        }
        let input = try C09OperationsMetricsTestSupport.project(subject: subject, exposures: [exposure], segments: [segment])
        let dashboard = try DashboardProjectionV1(input: input)
        let canonical = try WorkspaceMutationCanonicalV1.data(dashboard)
        XCTAssertEqual(canonical, try WorkspaceMutationCanonicalV1.data(DashboardProjectionV1(input: input)))
        XCTAssertThrowsError(try C09OperationsMetricsTestSupport.decoder().decode(
            DashboardProjectionV1.self,
            from: Data(canonical.dropLast())
        )) { _ in }

        var corruptJSON = try JSONSerialization.jsonObject(with: canonical) as! [String: Any]
        corruptJSON["dashboardSHA256"] = C09OperationsMetricsTestSupport.digest("f")
        let corrupt = try C09OperationsMetricsTestSupport.decoder().decode(
            DashboardProjectionV1.self,
            from: JSONSerialization.data(withJSONObject: corruptJSON, options: [.sortedKeys])
        )
        XCTAssertThrowsError(try corrupt.validate()) { error in
            XCTAssertEqual(error as? OperationsMetricsFailureV1, .definitionOutputDisagreement)
        }
        XCTAssertEqual(OperationsMetricsDerivedLifecycleV1.storage, "NONPERSISTENT_DERIVED_ONLY")
        XCTAssertEqual(OperationsMetricsDerivedLifecycleV1.retry, "REBUILD_FROM_CANONICAL_C53_INPUTS_WITH_UNIQUE_EVENT_REVISION")
        XCTAssertEqual(OperationsMetricsDerivedLifecycleV1.replay, "REBUILD_FROM_CANONICAL_C53_INPUTS")
        XCTAssertEqual(OperationsMetricsDerivedLifecycleV1.deletion, "DROP_DERIVED_AND_REBUILD")
        XCTAssertTrue(corpus.lifecycle.contains("CORRUPT_DERIVED_FAIL_CLOSED"))
    }

    func testV23P04C09R01DropRebuildAndRecoveryPreserveCanonicalRecordsReceiptsAndArtifacts() async throws {
        let corpus = try C09OperationsMetricsTestSupport.fixture()
        check(corpus, id: "R01", tier: "RECOVERY", selector: #function)
        let recovery = corpus.recovery
        XCTAssertTrue(recovery.dropDerivedState)
        XCTAssertTrue(recovery.rebuildFromC53Inputs)
        XCTAssertTrue(recovery.canonicalRecordsPreserved)
        XCTAssertTrue(recovery.receiptsPreserved)
        XCTAssertTrue(recovery.reportsPreserved)
        XCTAssertTrue(recovery.exportsPreserved)
        XCTAssertTrue(recovery.privacyPreserved)
        XCTAssertFalse(corpus.containsCustomerData || corpus.containsSecrets)
        XCTAssertTrue(corpus.claims.noTelemetry)
        XCTAssertTrue(corpus.claims.derivedOnly)

        try OperationsMetricsContractV1.validateRegistry()
        let subject = try C09OperationsMetricsTestSupport.subject()
        let exposure = try C09OperationsMetricsTestSupport.exposure(
            subject: subject,
            plannedExclusions: [try C09OperationsMetricsTestSupport.interval(10, 20)]
        )
        let incident = try C09OperationsMetricsTestSupport.incident(subject: subject)
        let segment = try C09OperationsMetricsTestSupport.segment(
            subject: subject,
            eventID: C09OperationsMetricsTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5419"),
            mutationID: try C09OperationsMetricsTestSupport.mutation("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A541A")
        )
        let sourceExposureBytes = try ServiceReliabilityCanonicalCodecV1.encode(exposure)
        let sourceIncidentBytes = try ServiceReliabilityCanonicalCodecV1.encode(incident)
        let sourceSegmentBytes = try ServiceReliabilityCanonicalCodecV1.encode(segment)
        let sourceEventBytes = [sourceExposureBytes, sourceIncidentBytes, sourceSegmentBytes]
        let receipt = try C09OperationsMetricsTestSupport.c53MutationReceipt(exposure: exposure)
        let receiptBytes = try WorkspaceMutationCanonicalV1.data(receipt)
        let receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(receipt)
        let mutationReceiptSHA256 = try receipt.mutationReceipt.canonicalSHA256()
        try receipt.mutationReceipt.validate()
        try ServiceReliabilityLimitsV1.digest(receipt.bundleSHA256)
        let input = try C09OperationsMetricsTestSupport.project(subject: subject, exposures: [exposure], segments: [segment])
        let timeline = try AssetServiceHistoryTimelineV1(
            workspaceID: C09OperationsMetricsTestSupport.workspace,
            subject: subject,
            incidents: [incident],
            impactSegments: [segment],
            exposures: [exposure]
        )
        let dashboard = try DashboardProjectionV1(input: input)
        let timelineBytes = try WorkspaceMutationCanonicalV1.data(timeline)
        let dashboardBytes = try WorkspaceMutationCanonicalV1.data(dashboard)

        let source = try C09OperationsMetricsTestSupport.source(
            subject: subject,
            incidents: [incident],
            exposures: [exposure],
            segments: [segment]
        )
        let rebuildCoordinator = OperationsMetricsRebuildCoordinatorV1()
        let firstRebuild = try await rebuildCoordinator.rebuild(sources: [source])
        let derived = try XCTUnwrap(firstRebuild.projections.first)
        try derived.validate()
        XCTAssertFalse(derived.openJSON.isEmpty)
        XCTAssertEqual(derived.dashboard, dashboard)
        XCTAssertEqual(derived.timeline, timeline)
        XCTAssertEqual(derived.reportProjection.sourceProjectionSHA256, derived.c53InputProjectionSHA256)
        XCTAssertEqual(derived.canonicalSourceClosureSHA256, try source.canonicalSourceClosureSHA256())
        XCTAssertEqual(derived.reportEnvelopes.map(\.projection), dashboard.metricProjections)
        let reportProjectionBytes = try WorkspaceMutationCanonicalV1.data(derived.reportProjection)
        let reportEnvelopeBytes = try WorkspaceMutationCanonicalV1.data(derived.reportEnvelopes)
        let openJSONBytes = derived.openJSON
        let retained = try await rebuildCoordinator.validateOrDiscard(derived)
        XCTAssertEqual(retained, derived)

        let invalidDerived = OperationsMetricsDerivedProjectionV1(
            dashboard: derived.dashboard,
            timeline: derived.timeline,
            reportProjection: derived.reportProjection,
            reportEnvelopes: derived.reportEnvelopes,
            openJSON: derived.openJSON,
            canonicalSourceClosureSHA256: C09OperationsMetricsTestSupport.digest("e")
        )
        do {
            _ = try await rebuildCoordinator.validateOrDiscard(invalidDerived, source: source)
            XCTFail("A derived value with a mismatched C53 closure must be discarded")
        } catch let error as OperationsMetricsRebuildFailureV1 {
            XCTAssertEqual(error, .corruptDerivedProjection)
        } catch {
            XCTFail("Expected corrupt-derived rejection, got \(error)")
        }

        let rebuiltInput = try C09OperationsMetricsTestSupport.project(subject: subject, exposures: [exposure], segments: [segment])
        let rebuiltTimeline = try AssetServiceHistoryTimelineV1(
            workspaceID: C09OperationsMetricsTestSupport.workspace,
            subject: subject,
            incidents: [incident],
            impactSegments: [segment],
            exposures: [exposure]
        )
        let rebuiltDashboard = try DashboardProjectionV1(input: rebuiltInput)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(rebuiltTimeline), timelineBytes)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(rebuiltDashboard), dashboardBytes)
        XCTAssertEqual(sourceEventBytes, [
            try ServiceReliabilityCanonicalCodecV1.encode(exposure),
            try ServiceReliabilityCanonicalCodecV1.encode(incident),
            try ServiceReliabilityCanonicalCodecV1.encode(segment)
        ])
        XCTAssertEqual(rebuiltDashboard, dashboard)
        XCTAssertEqual(rebuiltTimeline, timeline)

        let secondRebuild = try await rebuildCoordinator.rebuild(sources: [source])
        let rebuiltDerived = try XCTUnwrap(secondRebuild.projections.first)
        try rebuiltDerived.validate()
        XCTAssertEqual(rebuiltDerived, derived)
        XCTAssertEqual(rebuiltDerived.reportProjection, derived.reportProjection)
        XCTAssertEqual(rebuiltDerived.reportEnvelopes, derived.reportEnvelopes)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(rebuiltDerived.reportProjection), reportProjectionBytes)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(rebuiltDerived.reportEnvelopes), reportEnvelopeBytes)
        XCTAssertEqual(rebuiltDerived.openJSON, openJSONBytes)
        XCTAssertEqual(rebuiltDerived.canonicalSourceClosureSHA256, derived.canonicalSourceClosureSHA256)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(receipt), receiptBytes)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.sha256(receipt), receiptSHA256)
        XCTAssertEqual(try receipt.mutationReceipt.canonicalSHA256(), mutationReceiptSHA256)
        XCTAssertEqual(OperationsMetricsContractV1.dropAndRebuildDisposition, "DROP_DERIVED_AND_REBUILD_FROM_C53")
        XCTAssertEqual(OperationsMetricsContractV1.backupDisposition, "EXCLUDED_DERIVED_REBUILD")
        XCTAssertEqual(OperationsMetricsContractV1.retryDisposition, "REBUILD_FROM_UNIQUE_CANONICAL_EVENT_ID_AND_REVISION")
        XCTAssertEqual(OperationsMetricsDerivedLifecycleV1.restore, "DROP_DERIVED_AND_REBUILD")
        XCTAssertEqual(OperationsMetricsDerivedLifecycleV1.deletion, "DROP_DERIVED_AND_REBUILD")
        XCTAssertEqual(OperationsMetricsDerivedLifecycleV1.corruptState, "DISCARD_AND_FAIL_CLOSED_UNTIL_REBUILT")
        XCTAssertTrue(corpus.lifecycle.contains("BACKUP_EXCLUDES_DERIVED"))
        XCTAssertTrue(corpus.lifecycle.contains("REPORT_EXPORT_PRESERVED"))
    }

    private func check(
        _ corpus: C09OperationsMetricsCorpus,
        id: String,
        tier: String,
        selector: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(corpus.evidenceIDs.contains("V23-P04-C09-\(id)"), file: file, line: line)
        guard let entry = corpus.selectors.first(where: { $0.id == id }) else {
            XCTFail("Missing C09 selector \(id)", file: file, line: line)
            return
        }
        XCTAssertEqual(entry.tier, tier, file: file, line: line)
        XCTAssertEqual(entry.selector, selector, file: file, line: line)
    }

    private func expectedOwner(for kind: AssetServiceHistoryEventKindV1) -> AssetServiceHistorySourceOwnerV1 {
        switch kind {
        case .incident, .impactSegment, .qualifiedExposure:
            return .c53ServiceReliability
        case .placementChange:
            return .c37PlacementPose
        case .inspection:
            return .inspection
        case .finding:
            return .finding
        case .correctiveWork:
            return .correctiveWork
        case .recheck:
            return .recheck
        case .report:
            return .report
        case .evidenceAssociation:
            return .evidenceAssociation
        case .explicitAssetChange:
            return .explicitAssetChange
        }
    }
}
