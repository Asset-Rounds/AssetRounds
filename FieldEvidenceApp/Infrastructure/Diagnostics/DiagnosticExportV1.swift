import CryptoKit
import Foundation
import UIKit

struct DiagnosticAppContextV1: Codable, Equatable, Sendable {
    let build: String
    let version: String
}

struct DiagnosticDeviceContextV1: Codable, Equatable, Sendable {
    let model: String
    let osVersion: String
}

struct LaunchTimeMillisecondsV1: Codable, Equatable, Sendable {
    var from1000Through1999: Int64
    var from2000Up: Int64
    var from500Through999: Int64
    var under500: Int64

    static let zero = LaunchTimeMillisecondsV1(
        from1000Through1999: 0,
        from2000Up: 0,
        from500Through999: 0,
        under500: 0
    )

    var isValid: Bool {
        from1000Through1999 >= 0
            && from2000Up >= 0
            && from500Through999 >= 0
            && under500 >= 0
    }
}

struct MetricKitSummaryV1: Codable, Equatable, Sendable {
    let crashCount: Int64
    let hangCount: Int64
    let launchTimeMilliseconds: LaunchTimeMillisecondsV1?
    let peakMemoryBytes: Int64?

    var isValid: Bool {
        crashCount >= 0
            && hangCount >= 0
            && (launchTimeMilliseconds?.isValid ?? true)
            && (peakMemoryBytes.map { $0 >= 0 } ?? true)
    }
}

/// A bounded, privacy-safe summary of WorkPacket coordination. It carries
/// counts only: packet/item identifiers, actors, claim/lease payloads,
/// evidence, and result content never enter a diagnostic export.
struct WorkPacketDiagnosticSummaryV1: Codable, Equatable, Sendable {
    let packetCount: Int
    let itemCount: Int
    let claimedItemCount: Int
    let leasedItemCount: Int
    let releasedItemCount: Int
    let handedOffItemCount: Int
    let collisionCount: Int

    var isValid: Bool {
        let values = [
            packetCount,
            itemCount,
            claimedItemCount,
            leasedItemCount,
            releasedItemCount,
            handedOffItemCount,
            collisionCount,
        ]
        return values.allSatisfy { $0 >= 0 }
            && claimedItemCount <= itemCount
            && leasedItemCount <= itemCount
            && releasedItemCount <= itemCount
            && handedOffItemCount <= itemCount
            && collisionCount <= itemCount
    }
}

/// C29 aggregate-only plan health.  Diagnostics expose bounded counts and
/// lifecycle-state totals, never plan IDs, canonical bytes, content/locator
/// references, actor snapshots, component registries, or rebase digests.
struct PlanDiagnosticMetadataV1: Codable, Equatable, Sendable {
    let documentCount: Int
    let revisionCount: Int
    let placementCount: Int
    let rebaseReceiptCount: Int
    let activeDocumentCount: Int
    let retiredDocumentCount: Int
    let draftRevisionCount: Int
    let releasedRevisionCount: Int
    let withdrawnRevisionCount: Int
    let metadataOnly: Bool
    let derivedPreviewRebuilt: Bool
    let componentRegistryExcluded: Bool

    var isValid: Bool {
        let values = [
            documentCount, revisionCount, placementCount, rebaseReceiptCount,
            activeDocumentCount, retiredDocumentCount, draftRevisionCount,
            releasedRevisionCount, withdrawnRevisionCount,
        ]
        return values.allSatisfy { $0 >= 0 }
            && activeDocumentCount + retiredDocumentCount == documentCount
            && draftRevisionCount + releasedRevisionCount + withdrawnRevisionCount
                == revisionCount
            && metadataOnly
            && derivedPreviewRebuilt
            && componentRegistryExcluded
    }
}

/// C37 exposes only aggregate pose-health facts. Durable pose history and
/// spatial observations are never serialized into diagnostics; current tips,
/// completed snapshots, and axis registries are derived and rebuilt.
struct PlacementPoseDiagnosticMetadataV1: Codable, Equatable, Sendable {
    let poseEventCount: Int
    let spatialAnchorObservationCount: Int
    let currentTipCount: Int
    let completedSnapshotCount: Int
    let metadataOnly: Bool
    let immutableHistoryPreserved: Bool
    let derivedProjectionRebuilt: Bool
    let sensorProposalPersistence: String

    var isValid: Bool {
        [
            poseEventCount, spatialAnchorObservationCount,
            currentTipCount, completedSnapshotCount,
        ].allSatisfy { $0 >= 0 && $0 <= 100_000 }
            && metadataOnly
            && immutableHistoryPreserved
            && derivedProjectionRebuilt
            && sensorProposalPersistence == "NONPERSISTENT"
    }
}

struct DiagnosticExportV1: Codable, Equatable, Sendable {
    let app: DiagnosticAppContextV1
    let counters: DiagnosticsV1
    let device: DiagnosticDeviceContextV1
    let diagnosticSchemaVersion: Int
    let generatedAt: Date
    let metricKit: MetricKitSummaryV1?
    /// Optional frozen assurance evidence.  The default remains nil until the
    /// owning production finalization surface is activated.
    var requirementAssurance: RequirementAssuranceSnapshotV1? = nil
    /// Optional WorkPacket coordination counts. This is deliberately a
    /// summary-only surface and is absent unless the caller supplies it.
    var workPacket: WorkPacketDiagnosticSummaryV1? = nil
    /// Optional C19 metadata-only summary. Exact values, units, actor
    /// snapshots, opaque serials, and evidence references are never diagnostic
    /// payload and therefore do not appear here.
    var measurementIntegrity: MeasurementIntegrityDiagnosticMetadataV1? = nil
    /// Optional C20 metadata-only privacy-transform health summary. It carries
    /// counts and denial states, never content bytes, content identifiers,
    /// review rationale, or reviewer identity.
    var privacyTransform: PrivacyTransformDiagnosticMetadataV1? = nil
    /// Optional C21 metadata-only local admission/lifecycle summary. It
    /// carries closed state values and permissions only; no device/user,
    /// endpoint/provider/account, payload, or delivery acknowledgement data.
    var clientCapability: ClientCapabilityDiagnosticMetadataV1? = nil
    /// Optional C22 recovery verification health. It carries only bounded
    /// counts and closed dispositions; archive bytes, content/state digests,
    /// staging locators, verifier identity, and client-capability bindings are
    /// never diagnostic payload.
    var recoverabilityVerification: RecoverabilityVerificationDiagnosticMetadataV1? = nil
    /// Optional C23 release/binding/readiness health summary. It contains
    /// bounded counts and closed states only; reference bytes, content IDs,
    /// locators, license notices, and subject identity are excluded.
    var fieldReference: FieldReferenceDiagnosticMetadataV1? = nil
    /// Optional C24 aggregate-only semantic-tree health. Node text, node and
    /// evidence identifiers, locators, original bytes, and assessor identity
    /// are intentionally absent.
    var accessibleDocument: AccessibleDocumentDiagnosticMetadataV1? = nil
    /// Optional C28 aggregate-only schedule health. Release/history payloads,
    /// occurrence identities, actor snapshots, and due/reminder identifiers
    /// are never diagnostic material.
    var schedule: ScheduleDiagnosticMetadataV1? = nil
    /// Optional C29 aggregate-only plan health. Immutable plan bytes and
    /// component-registry/rebase payloads are excluded from diagnostics.
    var plan: PlanDiagnosticMetadataV1? = nil
    /// Optional C37 aggregate-only pose health. Event/observation bytes,
    /// actors, asset identities, and spatial coordinates are excluded.
    var placementPose: PlacementPoseDiagnosticMetadataV1? = nil

    /// Integration event payloads, subjects, cursors, and checkpoint bytes are
    /// never diagnostic material. Diagnostics may describe only the static
    /// drop-and-rebuild posture through code-owned policy.
    var integrationProjectionPayloadExcluded: Bool {
        IntegrationProjectionSchemaV1.persistenceMode == "DERIVED_ONLY"
            && !IntegrationProjectionSchemaV1.canonicalExportIncluded
            && !IntegrationProjectionSchemaV1.canonicalReportSource
    }

    var isValid: Bool {
        diagnosticSchemaVersion == 1
            && app.build.isDiagnosticSystemValue
            && app.version.isDiagnosticSystemValue
            && counters.isValid
            && device.model.isDiagnosticSystemValue
            && device.osVersion.isDiagnosticSystemValue
            && generatedAt.timeIntervalSinceReferenceDate.isFinite
            && (metricKit?.isValid ?? true)
            && (requirementAssurance.map {
                RequirementAssuranceSnapshotCanonicalCodecV1.isValid($0)
            } ?? true)
            && (workPacket?.isValid ?? true)
            && (measurementIntegrity?.isValid ?? true)
            && (privacyTransform?.isValid ?? true)
            && (clientCapability?.isValid ?? true)
            && (recoverabilityVerification?.isValid ?? true)
            && (fieldReference?.isValid ?? true)
            && (accessibleDocument?.isValid ?? true)
            && (schedule?.isValid ?? true)
            && (plan?.isValid ?? true)
            && (placementPose?.isValid ?? true)
            && integrationProjectionPayloadExcluded
    }

    var requirementExplanations: [RequirementExplanationItemV1] {
        requirementAssurance.map {
            RequirementExplanationProjectionV1.project($0.evaluations)
        } ?? []
    }
}

struct PreparedDiagnosticExportV1: Equatable, Sendable {
    let value: DiagnosticExportV1
    let canonicalData: Data
}

enum DiagnosticExportError: Error, Equatable {
    case invalidValue
}

enum IntegrationProjectionDiagnosticExclusionV1 {
    static let forbiddenJSONKeys = [
        "checkpointSHA256", "consumerStateSHA256", "eventID",
        "eventSHA256", "lastEventID", "lastEventSHA256", "payloadSHA256",
        "sourceReceiptSHA256", "subjectSemanticSHA256",
        // C22 archive, replay, staging, receipt, and verifier bindings are
        // evidence fields, never diagnostic material.
        "archiveSHA256", "archiveManifestSHA256", "recordsSHA256",
        "contentManifestSHA256", "checkpointFrontierSHA256",
        "orderedMutationDigestSHA256", "restoredCanonicalStateSHA256",
        "replayedCanonicalStateSHA256", "stagingLocatorToken",
        "sourceArchiveReadbackSHA256", "liveWorkspaceStateBeforeSHA256",
        "liveWorkspaceStateAfterSHA256", "sourceArchiveSHA256Before",
        "sourceArchiveSHA256After", "semanticBuildID", "executableSHA256",
        "restoredRecordsSHA256", "expectedContentManifestSHA256",
        "restoredContentManifestSHA256", "missingContentSHA256s",
        "reconciliationSHA256", "replaySHA256", "cleanupSHA256",
        "sourceWorkspaceID", "sourceGenerationID", "archiveByteCount",
        "persistentSchemaVersion", "recordsSchemaVersion", "workspaceID",
        "decisionID", "decisionSHA256", "receiptSHA256", "receiptID",
        "verificationID", "stagingID", "checkpointID", "mutationID",
        // C23 reference bytes, locators, license notices, subject identity,
        // and release/binding provenance are not diagnostic material.
        "releaseID", "bindingID", "referencePackID", "sourceName",
        "sourceReleaseIdentifier", "licenseNotice", "subjectID",
        "contentID", "locatorID", "releaseSHA256", "manifestSHA256",
        "readinessSHA256", "projectionSHA256", "canonicalData", "bytes",
        "restrictedContent", "assetID", "lookupKey", "namespaceID",
        "normalizedValueSHA256", "publicKeyData", "publicKeySHA256",
        "signatureData", "signatureSHA256", "externalKey", "signedPayload",
        "signingKey", "rawBytes", "actorID", "actorIdentity",
        // C24 semantic-tree and assessment details are not diagnostics.
        "nodeID", "parentNodeID", "evidenceID", "evidenceSHA256",
        "localizedText", "alternateText", "assessor", "assessorID",
        "privateEvidence", "originalBytes", "pdfUAClaimed", "wcagClaimed",
        "legalCertificationClaimed", "s10BrandReconciled",
    ]

    static func validate(_ data: Data) throws {
        guard IntegrationProjectionSchemaV1.persistenceMode == "DERIVED_ONLY",
              !IntegrationProjectionSchemaV1.canonicalExportIncluded,
              forbiddenJSONKeys.allSatisfy({ key in
                  data.range(of: Data("\"\(key)\"".utf8)) == nil
              }) else { throw DiagnosticExportError.invalidValue }
    }
}

struct C30EvidenceContextDiagnosticMetadataV1: Codable, Equatable, Sendable {
    let contextCount: Int
    let pairedLinkCount: Int
    let workspaceCount: Int
    let canonicalBytesIncluded: Bool
    let inferredContextIncluded: Bool
}

enum C30EvidenceContextDiagnosticPrivacyV1 {
    static func metadata(contexts: [EvidenceContextV1],
                         links: [PairedObservationLinkV1]) throws
        -> C30EvidenceContextDiagnosticMetadataV1 {
        try contexts.forEach { try $0.validateIntrinsic() }
        try links.forEach { try $0.validateIntrinsic() }
        let workspaces = Set(contexts.map(\.workspaceID) + links.map(\.workspaceID))
        return .init(contextCount: contexts.count, pairedLinkCount: links.count,
                     workspaceCount: workspaces.count, canonicalBytesIncluded: false,
                     inferredContextIncluded: false)
    }
}

struct DiagnosticExportService {
    typealias CountersProvider = () async -> DiagnosticsV1
    typealias MetricKitProvider = () -> MetricKitSummaryV1?
    typealias RequirementAssuranceProvider = () -> RequirementAssuranceSnapshotV1?
    typealias WorkPacketProvider = () -> WorkPacketDiagnosticSummaryV1?
    typealias ClientCapabilityProvider = () -> ClientCapabilityDiagnosticMetadataV1?
    typealias RecoverabilityVerificationProvider = () -> RecoverabilityVerificationDiagnosticMetadataV1?
    typealias FieldReferenceProvider = () -> FieldReferenceDiagnosticMetadataV1?
    typealias AccessibleDocumentProvider = () -> AccessibleDocumentDiagnosticMetadataV1?
    typealias ScheduleProvider = () -> ScheduleDiagnosticMetadataV1?
    typealias PlanProvider = () -> PlanDiagnosticMetadataV1?
    typealias PlacementPoseProvider = () -> PlacementPoseDiagnosticMetadataV1?
    typealias ContextProvider<Value> = () -> Value
    typealias Clock = () -> Date

    private let countersProvider: CountersProvider
    private let metricKitProvider: MetricKitProvider
    private let requirementAssuranceProvider: RequirementAssuranceProvider
    private let workPacketProvider: WorkPacketProvider
    private let clientCapabilityProvider: ClientCapabilityProvider
    private let recoverabilityVerificationProvider: RecoverabilityVerificationProvider
    private let fieldReferenceProvider: FieldReferenceProvider
    private let accessibleDocumentProvider: AccessibleDocumentProvider
    private let scheduleProvider: ScheduleProvider
    private let planProvider: PlanProvider
    private let placementPoseProvider: PlacementPoseProvider
    private let appProvider: ContextProvider<DiagnosticAppContextV1>
    private let deviceProvider: ContextProvider<DiagnosticDeviceContextV1>
    private let clock: Clock

    init(
        counters: @escaping CountersProvider,
        metricKit: @escaping MetricKitProvider,
        app: @escaping ContextProvider<DiagnosticAppContextV1>,
        device: @escaping ContextProvider<DiagnosticDeviceContextV1>,
        clock: @escaping Clock,
        requirementAssurance: @escaping RequirementAssuranceProvider = { nil },
        workPacket: @escaping WorkPacketProvider = { nil },
        clientCapability: @escaping ClientCapabilityProvider = { nil },
        recoverabilityVerification: @escaping RecoverabilityVerificationProvider = { nil },
        fieldReference: @escaping FieldReferenceProvider = { nil },
        accessibleDocument: @escaping AccessibleDocumentProvider = { nil },
        schedule: @escaping ScheduleProvider = { nil },
        plan: @escaping PlanProvider = { nil },
        placementPose: @escaping PlacementPoseProvider = { nil }
    ) {
        countersProvider = counters
        metricKitProvider = metricKit
        requirementAssuranceProvider = requirementAssurance
        workPacketProvider = workPacket
        clientCapabilityProvider = clientCapability
        recoverabilityVerificationProvider = recoverabilityVerification
        fieldReferenceProvider = fieldReference
        accessibleDocumentProvider = accessibleDocument
        scheduleProvider = schedule
        planProvider = plan
        placementPoseProvider = placementPose
        appProvider = app
        deviceProvider = device
        self.clock = clock
    }

    @MainActor
    init(
        diagnosticsStore: DiagnosticsStore,
        metricKitAdapter: MetricKitDiagnosticsAdapter,
        requirementAssurance: @escaping RequirementAssuranceProvider = { nil },
        workPacket: @escaping WorkPacketProvider = { nil },
        clientCapability: @escaping ClientCapabilityProvider = { nil },
        recoverabilityVerification: @escaping RecoverabilityVerificationProvider = { nil },
        fieldReference: @escaping FieldReferenceProvider = { nil },
        accessibleDocument: @escaping AccessibleDocumentProvider = { nil },
        schedule: @escaping ScheduleProvider = { nil },
        plan: @escaping PlanProvider = { nil },
        placementPose: @escaping PlacementPoseProvider = { nil },
        bundle: Bundle = .main,
        device: UIDevice = .current,
        clock: @escaping Clock = Date.init
    ) {
        let app = DiagnosticAppContextV1(
            build: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "Unavailable",
            version: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "Unavailable"
        )
        let device = DiagnosticDeviceContextV1(
            model: device.model,
            osVersion: device.systemVersion
        )
        self.init(
            counters: { await diagnosticsStore.snapshot() },
            metricKit: { metricKitAdapter.snapshot() },
            app: { app },
            device: { device },
            clock: clock,
            requirementAssurance: requirementAssurance,
            workPacket: workPacket,
            clientCapability: clientCapability,
            recoverabilityVerification: recoverabilityVerification,
            fieldReference: fieldReference,
            accessibleDocument: accessibleDocument,
            schedule: schedule,
            plan: plan,
            placementPose: placementPose
        )
    }

    func prepare() async throws -> PreparedDiagnosticExportV1 {
        let value = DiagnosticExportV1(
            app: appProvider(),
            counters: await countersProvider(),
            device: deviceProvider(),
            diagnosticSchemaVersion: 1,
            generatedAt: clock(),
            metricKit: metricKitProvider(),
            requirementAssurance: requirementAssuranceProvider(),
            workPacket: workPacketProvider(),
            clientCapability: clientCapabilityProvider(),
            recoverabilityVerification: recoverabilityVerificationProvider(),
            fieldReference: fieldReferenceProvider(),
            accessibleDocument: accessibleDocumentProvider(),
            schedule: scheduleProvider(),
            plan: planProvider(),
            placementPose: placementPoseProvider()
        )
        guard value.isValid else {
            throw DiagnosticExportError.invalidValue
        }
        let canonicalData = try DiagnosticExportCanonicalEncoderV1.encode(value)
        try IntegrationProjectionDiagnosticExclusionV1.validate(canonicalData)
        return PreparedDiagnosticExportV1(value: value, canonicalData: canonicalData)
    }
}

enum DiagnosticExportCanonicalEncoderV1 {
    static func encode(_ value: DiagnosticExportV1) throws -> Data {
        guard value.isValid else {
            throw DiagnosticExportError.invalidValue
        }
        var object: [String: CanonicalJSONValueV1] = [
            "app": .object([
                "build": .string(value.app.build),
                "version": .string(value.app.version),
            ]),
            "counters": try counters(value.counters),
            "device": .object([
                "model": .string(value.device.model),
                "osVersion": .string(value.device.osVersion),
            ]),
            "diagnosticSchemaVersion": .integer(value.diagnosticSchemaVersion),
            "generatedAt": CanonicalJSONV1.date(value.generatedAt),
            "metricKit": try value.metricKit.map(metricKit) ?? .null,
        ]
        if let assurance = value.requirementAssurance {
            object["requirementAssurance"] = CanonicalJSONV1.requirementAssurance(assurance)
        }
        if let workPacket = value.workPacket {
            object["workPacket"] = workPacketValue(workPacket)
        }
        if let measurementIntegrity = value.measurementIntegrity {
            object["measurementIntegrity"] = measurementIntegrityValue(measurementIntegrity)
        }
        if let privacyTransform = value.privacyTransform {
            object["privacyTransform"] = privacyTransformValue(privacyTransform)
        }
        if let clientCapability = value.clientCapability {
            object["clientCapability"] = clientCapabilityValue(clientCapability)
        }
        if let recoverabilityVerification = value.recoverabilityVerification {
            object["recoverabilityVerification"] = recoverabilityVerificationValue(
                recoverabilityVerification
            )
        }
        if let fieldReference = value.fieldReference {
            object["fieldReference"] = fieldReferenceValue(fieldReference)
        }
        if let accessibleDocument = value.accessibleDocument {
            object["accessibleDocument"] = accessibleDocumentValue(accessibleDocument)
        }
        if let schedule = value.schedule {
            object["schedule"] = scheduleValue(schedule)
        }
        if let plan = value.plan {
            object["plan"] = planValue(plan)
        }
        if let placementPose = value.placementPose {
            object["placementPose"] = placementPoseValue(placementPose)
        }
        let data = try CanonicalJSONV1.encode(.object(object))
        try IntegrationProjectionDiagnosticExclusionV1.validate(data)
        return data
    }

    private static func workPacketValue(
        _ value: WorkPacketDiagnosticSummaryV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "claimedItemCount": .integer(value.claimedItemCount),
            "collisionCount": .integer(value.collisionCount),
            "handedOffItemCount": .integer(value.handedOffItemCount),
            "itemCount": .integer(value.itemCount),
            "leasedItemCount": .integer(value.leasedItemCount),
            "packetCount": .integer(value.packetCount),
            "releasedItemCount": .integer(value.releasedItemCount),
        ])
    }

    private static func measurementIntegrityValue(
        _ value: MeasurementIntegrityDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "captureCount": .integer(value.captureCount),
            "seriesCount": .integer(value.seriesCount),
            "qualityAssessmentCount": .integer(value.qualityAssessmentCount),
            "calibrationStatuses": .array(value.calibrationStatuses.map { .string($0.rawValue) }),
            "qualityResults": .array(value.qualityResults.map { .string($0.rawValue) }),
            "sourceModes": .array(value.sourceModes.map { .string($0.rawValue) }),
            "policyVersion": .string(value.policyVersion),
            "metadataOnly": .bool(value.metadataOnly),
            "excludesCanonicalValues": .bool(value.excludesCanonicalValues),
            "excludesOpaqueSerials": .bool(value.excludesOpaqueSerials),
            "excludesOperatorIdentity": .bool(value.excludesOperatorIdentity),
            "excludesEvidenceLocators": .bool(value.excludesEvidenceLocators),
        ])
    }

    private static func privacyTransformValue(
        _ value: PrivacyTransformDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "manifestCount": .integer(value.manifestCount),
            "approvedDerivativeCount": .integer(value.approvedDerivativeCount),
            "deniedProjectionCount": .integer(value.deniedProjectionCount),
            "denialStates": .array(value.denialStates.map { .string($0.rawValue) }),
            "redactionDeclarationsCount": .integer(value.redactionDeclarationsCount),
            "policyVersion": .string(value.policyVersion),
            "metadataOnly": .bool(value.metadataOnly),
            "excludesDerivativeBytes": .bool(value.excludesDerivativeBytes),
            "excludesOriginalBytes": .bool(value.excludesOriginalBytes),
            "excludesReviewRationale": .bool(value.excludesReviewRationale),
            "excludesReviewerIdentity": .bool(value.excludesReviewerIdentity),
            "excludesSourceContentIdentifiers": .bool(value.excludesSourceContentIdentifiers),
        ])
    }

    private static func clientCapabilityValue(
        _ value: ClientCapabilityDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "admission": .string(value.admission.rawValue),
            "lifecycleState": .string(value.lifecycleState.rawValue),
            "operation": .string(value.operation.rawValue),
            "reasonCodes": .array(value.reasonCodes.map { .string($0.rawValue) }),
            "readAllowed": .bool(value.readAllowed),
            "writeAllowed": .bool(value.writeAllowed),
            "historicExportAllowed": .bool(value.historicExportAllowed),
            "withdrawalBlocksNewWork": .bool(value.withdrawalBlocksNewWork),
            "metadataOnly": .bool(value.metadataOnly),
            "immutableHistoric": .bool(value.immutableHistoric),
            "excludesDeviceAndUserIdentity": .bool(value.excludesDeviceAndUserIdentity),
            "excludesEndpointProviderAccount": .bool(value.excludesEndpointProviderAccount),
            "excludesRemoteDeliveryAcknowledgement": .bool(
                value.excludesRemoteDeliveryAcknowledgement
            ),
        ])
    }

    private static func recoverabilityVerificationValue(
        _ value: RecoverabilityVerificationDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "stagingCount": .integer(value.stagingCount),
            "receiptCount": .integer(value.receiptCount),
            "passedCount": .integer(value.passedCount),
            "failedCount": .integer(value.failedCount),
            "unsupportedCount": .integer(value.unsupportedCount),
            "quarantinedCount": .integer(value.quarantinedCount),
            "cancelledCount": .integer(value.cancelledCount),
            "modes": .array(value.modes.map { .string($0.rawValue) }),
            "freshnessDispositions": .array(
                value.freshnessDispositions.map { .string($0.rawValue) }
            ),
            "stagingStates": .array(value.stagingStates.map { .string($0.rawValue) }),
            "findingCodes": .array(value.findingCodes.map { .string($0.rawValue) }),
            "replayReceiptCount": .integer(value.replayReceiptCount),
            "reconciledReplayCount": .integer(value.reconciledReplayCount),
            "contentReconciliationCount": .integer(value.contentReconciliationCount),
            "completeContentReconciliationCount": .integer(
                value.completeContentReconciliationCount
            ),
            "cleanupProofCount": .integer(value.cleanupProofCount),
            "isolatedCleanupCount": .integer(value.isolatedCleanupCount),
            "policyVersion": .string(value.policyVersion),
            "metadataOnly": .bool(value.metadataOnly),
            "excludesArchiveBytes": .bool(value.excludesArchiveBytes),
            "excludesContentDigests": .bool(value.excludesContentDigests),
            "excludesStagingLocator": .bool(value.excludesStagingLocator),
            "excludesVerifierBuild": .bool(value.excludesVerifierBuild),
            "excludesClientCapability": .bool(value.excludesClientCapability),
        ])
    }

    private static func fieldReferenceValue(
        _ value: FieldReferenceDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "releaseCount": .integer(value.releaseCount),
            "bindingCount": .integer(value.bindingCount),
            "readyOfflineCount": .integer(value.readyOfflineCount),
            "missingBytesCount": .integer(value.missingBytesCount),
            "expiredCount": .integer(value.expiredCount),
            "revokedCount": .integer(value.revokedCount),
            "supersededCount": .integer(value.supersededCount),
            "staleBindingCount": .integer(value.staleBindingCount),
            "protectedDataUnavailableCount": .integer(value.protectedDataUnavailableCount),
            "unavailableCount": .integer(value.unavailableCount),
            "availabilityStates": .array(value.availabilityStates.map { .string($0.rawValue) }),
            "policyVersion": .string(value.policyVersion),
            "metadataOnly": .bool(value.metadataOnly),
            "excludesReferenceBytes": .bool(value.excludesReferenceBytes),
            "excludesContentIDs": .bool(value.excludesContentIDs),
            "excludesPrivateLocators": .bool(value.excludesPrivateLocators),
            "excludesLicenseSecrets": .bool(value.excludesLicenseSecrets),
            "excludesSubjectIdentity": .bool(value.excludesSubjectIdentity),
        ])
    }

    private static func accessibleDocumentValue(
        _ value: AccessibleDocumentDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "treeCount": .integer(value.treeCount),
            "customerSafeTreeCount": .integer(value.customerSafeTreeCount),
            "nodeCount": .integer(value.nodeCount),
            "documentNodeCount": .integer(value.documentNodeCount),
            "sectionNodeCount": .integer(value.sectionNodeCount),
            "headingNodeCount": .integer(value.headingNodeCount),
            "paragraphNodeCount": .integer(value.paragraphNodeCount),
            "listNodeCount": .integer(value.listNodeCount),
            "listItemNodeCount": .integer(value.listItemNodeCount),
            "tableNodeCount": .integer(value.tableNodeCount),
            "tableRowNodeCount": .integer(value.tableRowCount),
            "tableHeaderNodeCount": .integer(value.tableHeaderCount),
            "tableCellNodeCount": .integer(value.tableCellCount),
            "figureNodeCount": .integer(value.figureCount),
            "evidenceLinkNodeCount": .integer(value.evidenceLinkNodeCount),
            "noteNodeCount": .integer(value.noteNodeCount),
            "decorativeFigureCount": .integer(value.decorativeFigureCount),
            "describedFigureCount": .integer(value.describedFigureCount),
            "missingAlternateTextFigureCount": .integer(
                value.missingAlternateTextFigureCount
            ),
            "assessmentCount": .integer(value.assessmentCount),
            "internalPassCount": .integer(value.internalPassCount),
            "internalFailCount": .integer(value.internalFailCount),
            "incompleteCount": .integer(value.incompleteCount),
            "externallyProvedCount": .integer(value.externallyProvedCount),
            "assessmentStates": .array(
                value.assessmentStates.map { .string($0.rawValue) }
            ),
            "policyVersion": .string(value.policyVersion),
            "metadataOnly": .bool(value.metadataOnly),
            "excludesOriginalEvidence": .bool(value.excludesOriginalEvidence),
            "excludesPrivateEvidence": .bool(value.excludesPrivateEvidence),
            "excludesAssessorIdentity": .bool(value.excludesAssessorIdentity),
            "excludesPrivateLocators": .bool(value.excludesPrivateLocators),
            "excludesUnsupportedClaims": .bool(value.excludesUnsupportedClaims),
        ])
    }

    private static func scheduleValue(
        _ value: ScheduleDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "definitionReleaseCount": .integer(value.definitionReleaseCount),
            "activeReleaseCount": .integer(value.activeReleaseCount),
            "occurrenceHistoryEventCount": .integer(value.occurrenceHistoryEventCount),
            "dueProjectionEntryCount": .integer(value.dueProjectionEntryCount),
            "reminderProjectionEntryCount": .integer(value.reminderProjectionEntryCount),
            "policyVersion": .string(value.policyVersion),
            "metadataOnly": .bool(value.metadataOnly),
            "excludesSchedulePayload": .bool(value.excludesSchedulePayload),
            "excludesOccurrenceIdentity": .bool(value.excludesOccurrenceIdentity),
            "excludesActorIdentity": .bool(value.excludesActorIdentity),
            "excludesNotificationState": .bool(value.excludesNotificationState),
        ])
    }

    private static func planValue(
        _ value: PlanDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "documentCount": .integer(value.documentCount),
            "revisionCount": .integer(value.revisionCount),
            "placementCount": .integer(value.placementCount),
            "rebaseReceiptCount": .integer(value.rebaseReceiptCount),
            "activeDocumentCount": .integer(value.activeDocumentCount),
            "retiredDocumentCount": .integer(value.retiredDocumentCount),
            "draftRevisionCount": .integer(value.draftRevisionCount),
            "releasedRevisionCount": .integer(value.releasedRevisionCount),
            "withdrawnRevisionCount": .integer(value.withdrawnRevisionCount),
            "metadataOnly": .bool(value.metadataOnly),
            "derivedPreviewRebuilt": .bool(value.derivedPreviewRebuilt),
            "componentRegistryExcluded": .bool(value.componentRegistryExcluded),
        ])
    }

    private static func placementPoseValue(
        _ value: PlacementPoseDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "poseEventCount": .integer(value.poseEventCount),
            "spatialAnchorObservationCount": .integer(
                value.spatialAnchorObservationCount
            ),
            "currentTipCount": .integer(value.currentTipCount),
            "completedSnapshotCount": .integer(value.completedSnapshotCount),
            "metadataOnly": .bool(value.metadataOnly),
            "immutableHistoryPreserved": .bool(value.immutableHistoryPreserved),
            "derivedProjectionRebuilt": .bool(value.derivedProjectionRebuilt),
            "sensorProposalPersistence": .string(value.sensorProposalPersistence),
        ])
    }

    private static func counters(
        _ value: DiagnosticsV1
    ) throws -> CanonicalJSONValueV1 {
        .object([
            "first_sign_created": try integer(value.firstSignCreated),
            "onboarding_completed": try integer(value.onboardingCompleted),
            "paywall_presented": try integer(value.paywallPresented),
            "purchase_result": .object([
                "cancelled": try integer(value.purchaseResult.cancelled),
                "failed": try integer(value.purchaseResult.failed),
                "pending": try integer(value.purchaseResult.pending),
                "unverified": try integer(value.purchaseResult.unverified),
                "verified": try integer(value.purchaseResult.verified),
            ]),
            "recheck_completed": try integer(value.recheckCompleted),
            "report_saved": try integer(value.reportSaved),
            "report_share_sheet_presented": try integer(
                value.reportShareSheetPresented
            ),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    private static func metricKit(
        _ value: MetricKitSummaryV1
    ) throws -> CanonicalJSONValueV1 {
        .object([
            "crashCount": try integer(value.crashCount),
            "hangCount": try integer(value.hangCount),
            "launchTimeMilliseconds": try value.launchTimeMilliseconds.map(
                launchTime
            ) ?? .null,
            "peakMemoryBytes": try value.peakMemoryBytes.map(integer) ?? .null,
        ])
    }

    private static func launchTime(
        _ value: LaunchTimeMillisecondsV1
    ) throws -> CanonicalJSONValueV1 {
        .object([
            "from1000Through1999": try integer(value.from1000Through1999),
            "from2000Up": try integer(value.from2000Up),
            "from500Through999": try integer(value.from500Through999),
            "under500": try integer(value.under500),
        ])
    }

    private static func integer(_ value: Int64) throws -> CanonicalJSONValueV1 {
        guard let exact = Int(exactly: value) else {
            throw DiagnosticExportError.invalidValue
        }
        return .integer(exact)
    }
}

private extension String {
    var isDiagnosticSystemValue: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return self == trimmed
            && !trimmed.isEmpty
            && trimmed.count <= 128
            && !unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

enum SupportBundleBuilderFailureV1: Error, Equatable, Sendable {
    case alreadyFinished
    case cancelled
    case cleanupFailed
    case invalidSource
    case sizeLimitExceeded
    case writeFailed
}

struct SupportExportCancellationV1: Sendable {
    static let never = SupportExportCancellationV1 { false }
    private let source: @Sendable () -> Bool

    init(_ source: @escaping @Sendable () -> Bool) {
        self.source = source
    }

    var isCancelled: Bool { source() }
}

private struct SupportBundlePayloadV1: Codable {
    let manifest: SupportBundleManifestV1
    let members: [String: Data]
}

/// Builds one explicit, local-only support artifact from an allowlist. It has
/// no uploader, network client, customer identifier, work payload, or raw-log
/// input. The caller owns presentation of the share sheet and must finish with
/// the explicit external-effect disposition after sharing or cancellation.
struct SupportBundleBuilderV1: Sendable {
    typealias DiagnosticProvider = @Sendable () async throws -> PreparedDiagnosticExportV1
    typealias SupportProvider = @Sendable () async throws -> DeviceOperationalSupportSnapshotV2
    typealias Clock = @Sendable () -> Date
    typealias IDSource = @Sendable () -> UUID

    private let diagnosticProvider: DiagnosticProvider
    private let supportProvider: SupportProvider
    private let scratch: any ScratchDataLeasePortV1
    private let clock: Clock
    private let idSource: IDSource

    init(
        diagnostic: @escaping DiagnosticProvider,
        support: @escaping SupportProvider,
        scratch: any ScratchDataLeasePortV1,
        clock: @escaping Clock,
        idSource: @escaping IDSource
    ) {
        diagnosticProvider = diagnostic
        supportProvider = support
        self.scratch = scratch
        self.clock = clock
        self.idSource = idSource
    }

    func prepare(
        mode: SupportBundleModeV1,
        cancellation: SupportExportCancellationV1 = .never
    ) async throws -> SupportExportResultV1 {
        if cancellation.isCancelled {
            return try SupportExportResultV1(
                disposition: .cancelled,
                manifest: nil,
                lease: nil,
                fileURL: nil
            )
        }
        let diagnostic: PreparedDiagnosticExportV1
        do {
            diagnostic = try await diagnosticProvider()
            guard diagnostic.canonicalData.count
                    <= SupportBundleManifestV1.maximumCanonicalBytes else {
                throw SupportBundleBuilderFailureV1.sizeLimitExceeded
            }
            guard diagnostic.value.isValid,
                  try DiagnosticExportCanonicalEncoderV1.encode(
                      diagnostic.value
                  ) == diagnostic.canonicalData else {
                throw SupportBundleBuilderFailureV1.invalidSource
            }
        } catch let failure as SupportBundleBuilderFailureV1 {
            throw failure
        } catch {
            throw SupportBundleBuilderFailureV1.invalidSource
        }
        var members: [(SupportBundleMemberKindV1, String, Data)] = [
            (.diagnosticSummary, "diagnostic-summary.json", diagnostic.canonicalData)
        ]
        if mode == .full {
            do {
                let snapshot = try await supportProvider()
                try snapshot.health.validate()
                guard snapshot.counters.isValid else {
                    throw SupportBundleBuilderFailureV1.invalidSource
                }
                members.append((
                    .systemHealth,
                    "system-health.json",
                    try Self.encodeCanonical(snapshot)
                ))
            } catch let failure as SupportBundleBuilderFailureV1 {
                throw failure
            } catch {
                throw SupportBundleBuilderFailureV1.invalidSource
            }
        }
        if cancellation.isCancelled {
            return try SupportExportResultV1(
                disposition: .cancelled,
                manifest: nil,
                lease: nil,
                fileURL: nil
            )
        }
        let total = try members.reduce(0) { partial, member in
            let (next, overflow) = partial.addingReportingOverflow(member.2.count)
            guard !overflow, next <= SupportBundleManifestV1.maximumCanonicalBytes else {
                throw SupportBundleBuilderFailureV1.sizeLimitExceeded
            }
            return next
        }
        let generatedAt = clock()
        let bundleID = idSource()
        let entries = members.map { member in
            SupportBundleManifestEntryV1(
                kind: member.0,
                relativeName: member.1,
                byteCount: member.2.count,
                sha256: Self.sha256(member.2)
            )
        }
        let manifest = try SupportBundleManifestV1(
            bundleID: bundleID,
            mode: mode,
            generatedAt: generatedAt,
            entries: entries,
            totalCanonicalByteCount: total
        )
        let payload = try Self.encodeCanonical(SupportBundlePayloadV1(
            manifest: manifest,
            members: Dictionary(uniqueKeysWithValues: members.map { ($0.1, $0.2) })
        ))
        guard payload.count <= SupportBundleManifestV1.maximumCanonicalBytes else {
            throw SupportBundleBuilderFailureV1.sizeLimitExceeded
        }
        let lease = try await scratch.acquireScratchLease(
            try ScratchDataLeaseRequestV1(
                leaseID: idSource(),
                purpose: .supportExport,
                owner: .supportExport,
                ownerOperationID: bundleID,
                requestedByteCount: UInt64(SupportBundleManifestV1.maximumCanonicalBytes),
                createdAt: generatedAt,
                expiresAt: generatedAt.addingTimeInterval(
                    ScratchDataPurposeV1.supportExport.maximumLifetimeSeconds
                )
            )
        )
        if cancellation.isCancelled {
            try await release(lease, terminal: .cancelled)
            return try SupportExportResultV1(
                disposition: .cancelled,
                manifest: nil,
                lease: nil,
                fileURL: nil
            )
        }
        do {
            let url = try await scratch.writeScratchData(
                payload,
                named: "support-bundle.json",
                lease: lease
            )
            return try SupportExportResultV1(
                disposition: .prepared,
                manifest: manifest,
                lease: lease,
                fileURL: url
            )
        } catch {
            try await release(lease, terminal: .failed)
            throw SupportBundleBuilderFailureV1.writeFailed
        }
    }

    /// Called only after the caller knows whether the external share effect
    /// occurred. The returned closed receipt never claims sharing early.
    func finish(
        _ result: SupportExportResultV1,
        disposition: SupportExportDispositionV1
    ) async throws -> SupportExportResultV1 {
        guard result.disposition == .prepared, let lease = result.lease else {
            throw SupportBundleBuilderFailureV1.invalidSource
        }
        let terminal: ScratchDataLeaseTerminalV1
        switch disposition {
        case .shared: terminal = .completed
        case .cancelled: terminal = .cancelled
        case .failed: terminal = .failed
        case .expired: terminal = .recoveredExpired
        case .prepared:
            throw SupportBundleBuilderFailureV1.invalidSource
        }
        guard result.manifest != nil else {
            throw SupportBundleBuilderFailureV1.invalidSource
        }
        let receipt = try SupportExportResultV1(
            disposition: disposition,
            manifest: disposition == .shared ? result.manifest : nil,
            lease: nil,
            fileURL: nil
        )
        guard result.beginTerminalDisposition(disposition) else {
            throw SupportBundleBuilderFailureV1.alreadyFinished
        }
        do {
            try await release(lease, terminal: terminal)
        } catch {
            result.rollbackTerminalDisposition(disposition)
            throw error
        }
        result.commitTerminalDisposition(disposition)
        return receipt
    }

    private func release(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) async throws {
        do {
            try await scratch.releaseScratchLease(lease, terminal: terminal)
        } catch {
            throw SupportBundleBuilderFailureV1.cleanupFailed
        }
    }

    private static func encodeCanonical<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Metadata-only C18 diagnostics. No package bytes, draft payload, actor
/// identity, exact candidate head, or receipt digest is diagnostic material.
struct PackageEvolutionDiagnosticMetadataV1: Codable, Equatable, Sendable {
    let packageID: String
    let packageReleaseID: String
    let semanticClassification: PackageSemanticDiffClassificationV1
    let promotionStatus: PackageEvolutionConsumerStatusV1

    init(metadata: PackageEvolutionConsumerMetadataV1) throws {
        try metadata.validate()
        packageID = metadata.packageID
        packageReleaseID = metadata.packageReleaseID
        semanticClassification = metadata.semanticClassification
        promotionStatus = metadata.promotionStatus
        try validate()
    }

    init(bundle: PackagePromotionAtomicBundleV1) throws {
        try self.init(metadata: PackageEvolutionConsumerMetadataV1(bundle: bundle))
    }

    func validate() throws {
        guard InspectionPackageValidationV2.validIdentifier(packageID, maximumBytes: 200),
              KernelCanonicalHashV1.validSHA256(packageReleaseID) else {
            throw PackageEvolutionConsumerFailureV1.invalidMetadata
        }
    }

    static let includesCanonicalPackageBytes = false
    static let includesDraftPayload = false
    static let includesActorIdentity = false
    static let includesExactCandidateHead = false
}

extension DiagnosticExportV1 {
    static func packageEvolutionDiagnosticMetadata(
        _ metadata: PackageEvolutionConsumerMetadataV1
    ) throws -> PackageEvolutionDiagnosticMetadataV1 {
        try PackageEvolutionDiagnosticMetadataV1(metadata: metadata)
    }

    static func packageEvolutionDiagnosticMetadata(
        _ bundle: PackagePromotionAtomicBundleV1
    ) throws -> PackageEvolutionDiagnosticMetadataV1 {
        try PackageEvolutionDiagnosticMetadataV1(bundle: bundle)
    }
}

/// The diagnostic surface for C19 is intentionally a bounded health summary.
/// It can report counts and recorded dispositions, but never values, units,
/// operator identity, serials, response payloads, or evidence locators.
struct MeasurementIntegrityDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "MEASUREMENT_INTEGRITY_DIAGNOSTIC_V1"

    let schemaVersion: Int
    let captureCount: Int
    let seriesCount: Int
    let qualityAssessmentCount: Int
    let calibrationStatuses: [CalibrationStatusV1]
    let qualityResults: [MeasurementQualityResultV1]
    let sourceModes: [MeasurementCaptureSourceModeV1]
    let policyVersion: String
    let metadataOnly: Bool
    let excludesCanonicalValues: Bool
    let excludesOpaqueSerials: Bool
    let excludesOperatorIdentity: Bool
    let excludesEvidenceLocators: Bool

    init(
        captures: [MeasurementCaptureV1],
        series: [MeasurementSeriesV1] = [],
        qualityAssessments: [MeasurementQualityAssessmentV1] = [],
        calibrationStatuses: [CalibrationStatusV1] = []
    ) throws {
        try captures.forEach { try $0.validate() }
        try series.forEach { try $0.validate() }
        try qualityAssessments.forEach { try $0.validate() }
        guard captures.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              series.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              qualityAssessments.count <= MeasurementIntegrityLimitsV1.maximumSampleCount else {
            throw DiagnosticExportError.invalidValue
        }
        schemaVersion = Self.schemaVersion
        captureCount = captures.count
        seriesCount = series.count
        qualityAssessmentCount = qualityAssessments.count
        self.calibrationStatuses = Array(Set(calibrationStatuses.map(\.rawValue)))
            .compactMap(CalibrationStatusV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        qualityResults = Array(Set(qualityAssessments.map { $0.result.rawValue }))
            .compactMap(MeasurementQualityResultV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        sourceModes = Array(Set(captures.map { $0.sourceMode.rawValue }))
            .compactMap(MeasurementCaptureSourceModeV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesCanonicalValues = true
        excludesOpaqueSerials = true
        excludesOperatorIdentity = true
        excludesEvidenceLocators = true
        try validate()
    }

    var isValid: Bool {
        (try? validate()) != nil
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              captureCount >= 0, seriesCount >= 0, qualityAssessmentCount >= 0,
              calibrationStatuses == calibrationStatuses.sorted(by: { $0.rawValue < $1.rawValue }),
              qualityResults == qualityResults.sorted(by: { $0.rawValue < $1.rawValue }),
              sourceModes == sourceModes.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(calibrationStatuses.map(\.rawValue)).count == calibrationStatuses.count,
              Set(qualityResults.map(\.rawValue)).count == qualityResults.count,
              Set(sourceModes.map(\.rawValue)).count == sourceModes.count,
              policyVersion == Self.policyVersion,
              metadataOnly, excludesCanonicalValues, excludesOpaqueSerials,
              excludesOperatorIdentity, excludesEvidenceLocators else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

/// C20 diagnostics contain only bounded projection health facts. No content
/// identifier, digest, byte payload, actor identity, or review rationale is
/// retained in this type.
struct PrivacyTransformDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "PRIVACY_TRANSFORM_DIAGNOSTIC_V1"

    let schemaVersion: Int
    let manifestCount: Int
    let approvedDerivativeCount: Int
    let deniedProjectionCount: Int
    let denialStates: [PrivacyProjectionDenialV1]
    let redactionDeclarationsCount: Int
    let policyVersion: String
    let metadataOnly: Bool
    let excludesDerivativeBytes: Bool
    let excludesOriginalBytes: Bool
    let excludesReviewRationale: Bool
    let excludesReviewerIdentity: Bool
    let excludesSourceContentIdentifiers: Bool

    init(
        approvedProjections: [PrivacyTransformReportProjectionV1] = [],
        deniedProjectionStates: [PrivacyProjectionDenialV1] = [],
        manifestCount: Int? = nil
    ) throws {
        for projection in approvedProjections {
            try projection.validate()
        }
        let orderedDenials = deniedProjectionStates.sorted { $0.rawValue < $1.rawValue }
        guard Set(orderedDenials).count == orderedDenials.count,
              orderedDenials == Array(Set(orderedDenials)).sorted(by: { $0.rawValue < $1.rawValue }),
              approvedProjections.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              deniedProjectionStates.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              (manifestCount ?? approvedProjections.count) >= approvedProjections.count else {
            throw DiagnosticExportError.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.manifestCount = manifestCount ?? approvedProjections.count
        approvedDerivativeCount = approvedProjections.count
        deniedProjectionCount = deniedProjectionStates.count
        denialStates = orderedDenials
        redactionDeclarationsCount = approvedProjections.count
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesDerivativeBytes = true
        excludesOriginalBytes = true
        excludesReviewRationale = true
        excludesReviewerIdentity = true
        excludesSourceContentIdentifiers = true
        try validate()
    }

    var isValid: Bool { (try? validate()) != nil }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              manifestCount >= approvedDerivativeCount,
              approvedDerivativeCount >= 0,
              deniedProjectionCount >= 0,
              redactionDeclarationsCount == approvedDerivativeCount,
              denialStates == denialStates.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(denialStates).count == denialStates.count,
              policyVersion == Self.policyVersion,
              metadataOnly,
              excludesDerivativeBytes,
              excludesOriginalBytes,
              excludesReviewRationale,
              excludesReviewerIdentity,
              excludesSourceContentIdentifiers else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

/// C21 diagnostics expose only closed local admission/lifecycle facts. They
/// intentionally omit all IDs, digests, package payloads, user/device
/// identity, and any delivery or acknowledgement state.
struct ClientCapabilityDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "CLIENT_CAPABILITY_PACKAGE_LIFECYCLE_DIAGNOSTIC_V1"

    let schemaVersion: Int
    let admission: ClientAdmissionV1
    let lifecycleState: PackageLifecycleStateV1
    let operation: PackageLifecycleOperationV1
    let reasonCodes: [ClientCapabilityReasonV1]
    let readAllowed: Bool
    let writeAllowed: Bool
    let historicExportAllowed: Bool
    let withdrawalBlocksNewWork: Bool
    let metadataOnly: Bool
    let immutableHistoric: Bool
    let excludesDeviceAndUserIdentity: Bool
    let excludesEndpointProviderAccount: Bool
    let excludesRemoteDeliveryAcknowledgement: Bool

    init(projection: ClientCapabilityReportProjectionV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        admission = projection.admission
        lifecycleState = projection.lifecycleState
        operation = projection.operation
        reasonCodes = projection.reasons
        readAllowed = projection.readAllowed
        writeAllowed = projection.writeAllowed
        historicExportAllowed = projection.historicExportAllowed
        withdrawalBlocksNewWork = true
        metadataOnly = true
        immutableHistoric = projection.immutableHistoric
        excludesDeviceAndUserIdentity = true
        excludesEndpointProviderAccount = true
        excludesRemoteDeliveryAcknowledgement = true
        try validate()
    }

    var isValid: Bool { (try? validate()) != nil }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              reasonCodes == reasonCodes.sorted(by: { $0.rawValue < $1.rawValue }),
              !reasonCodes.isEmpty,
              Set(reasonCodes).count == reasonCodes.count,
              metadataOnly,
              immutableHistoric,
              withdrawalBlocksNewWork,
              excludesDeviceAndUserIdentity,
              excludesEndpointProviderAccount,
              excludesRemoteDeliveryAcknowledgement else {
            throw DiagnosticExportError.invalidValue
        }
        guard historicExportAllowed == (
            lifecycleState == .withdrawn
                && (admission == .readWrite || admission == .readOnly)
                && operation == .export
        ) else {
            throw DiagnosticExportError.invalidValue
        }
        guard writeAllowed == (
            admission == .readWrite
                && ClientCapabilityReportProjectionV1.writeOperations.contains(operation)
        ) else {
            throw DiagnosticExportError.invalidValue
        }
        guard readAllowed == (admission == .readWrite || admission == .readOnly) else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

/// C22 diagnostics are deliberately metadata-only.  They expose enough
/// bounded state to explain recovery freshness and replay/cleanup health, but
/// never carry archive bytes, content or canonical-state digests, staging
/// locators, verifier-build identity, client-capability bindings, or IDs.
struct RecoverabilityVerificationDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "RECOVERABILITY_VERIFICATION_DIAGNOSTIC_V1"
    static let maximumValues = 100_000

    let schemaVersion: Int
    let stagingCount: Int
    let receiptCount: Int
    let passedCount: Int
    let failedCount: Int
    let unsupportedCount: Int
    let quarantinedCount: Int
    let cancelledCount: Int
    let modes: [RecoverabilityVerificationModeV1]
    let freshnessDispositions: [RecoveryPointFreshnessDispositionV1]
    let stagingStates: [RecoverabilityStagingStateV1]
    let findingCodes: [RecoverabilityFindingCodeV1]
    let replayReceiptCount: Int
    let reconciledReplayCount: Int
    let contentReconciliationCount: Int
    let completeContentReconciliationCount: Int
    let cleanupProofCount: Int
    let isolatedCleanupCount: Int
    let policyVersion: String
    let metadataOnly: Bool
    let excludesArchiveBytes: Bool
    let excludesContentDigests: Bool
    let excludesStagingLocator: Bool
    let excludesVerifierBuild: Bool
    let excludesClientCapability: Bool

    init(
        receipts: [RecoverabilityVerificationReceiptV1] = [],
        staging: [RecoverabilityVerificationStagingV1] = []
    ) throws {
        guard receipts.count <= Self.maximumValues,
              staging.count <= Self.maximumValues else {
            throw DiagnosticExportError.invalidValue
        }
        try receipts.forEach { try $0.validate() }
        try staging.forEach { try $0.validate() }
        let receiptIDs = receipts.map { $0.receiptID }
        let stagingIDs = staging.map { $0.stagingID }
        guard Set(receiptIDs).count == receiptIDs.count,
              Set(stagingIDs).count == stagingIDs.count else {
            throw DiagnosticExportError.invalidValue
        }

        schemaVersion = Self.schemaVersion
        stagingCount = staging.count
        receiptCount = receipts.count
        passedCount = receipts.filter { $0.disposition == .passed }.count
        failedCount = receipts.filter { $0.disposition == .failed }.count
        unsupportedCount = receipts.filter { $0.disposition == .unsupported }.count
        quarantinedCount = receipts.filter { $0.disposition == .quarantined }.count
        cancelledCount = receipts.filter { $0.disposition == .cancelled }.count
        modes = Array(Set(receipts.map(
            \.mode.rawValue
        ))).compactMap(RecoverabilityVerificationModeV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        freshnessDispositions = Array(Set(receipts.map(
            \.freshness.rawValue
        ))).compactMap(RecoveryPointFreshnessDispositionV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        stagingStates = Array(Set(staging.map(
            \.state.rawValue
        ))).compactMap(RecoverabilityStagingStateV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        findingCodes = Array(Set(receipts.flatMap { $0.findings.map(\.rawValue) }))
            .compactMap(RecoverabilityFindingCodeV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        replayReceiptCount = receipts.reduce(into: 0) { count, receipt in
            if receipt.replayReceipt != nil { count += 1 }
        }
        reconciledReplayCount = receipts.reduce(into: 0) { count, receipt in
            if receipt.replayReceipt?.reconciles == true { count += 1 }
        }
        contentReconciliationCount = receipts.reduce(into: 0) { count, receipt in
            if receipt.contentReconciliation != nil { count += 1 }
        }
        completeContentReconciliationCount = receipts.reduce(into: 0) { count, receipt in
            if receipt.contentReconciliation?.isComplete == true { count += 1 }
        }
        cleanupProofCount = receipts.count
        isolatedCleanupCount = receipts.reduce(into: 0) { count, receipt in
            if receipt.cleanupProof.provesIsolation { count += 1 }
        }
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesArchiveBytes = true
        excludesContentDigests = true
        excludesStagingLocator = true
        excludesVerifierBuild = true
        excludesClientCapability = true
        try validate()
    }

    var isValid: Bool { (try? validate()) != nil }

    func validate() throws {
        let dispositionCount = passedCount + failedCount + unsupportedCount
            + quarantinedCount + cancelledCount
        guard schemaVersion == Self.schemaVersion,
              stagingCount >= 0, stagingCount <= Self.maximumValues,
              receiptCount >= 0, receiptCount <= Self.maximumValues,
              [passedCount, failedCount, unsupportedCount, quarantinedCount, cancelledCount]
                .allSatisfy { $0 >= 0 },
              dispositionCount == receiptCount,
              modes == modes.sorted(by: { $0.rawValue < $1.rawValue }),
              freshnessDispositions == freshnessDispositions.sorted(by: {
                  $0.rawValue < $1.rawValue
              }),
              stagingStates == stagingStates.sorted(by: { $0.rawValue < $1.rawValue }),
              findingCodes == findingCodes.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(modes).count == modes.count,
              Set(freshnessDispositions).count == freshnessDispositions.count,
              Set(stagingStates).count == stagingStates.count,
              Set(findingCodes).count == findingCodes.count,
              replayReceiptCount >= 0, replayReceiptCount <= receiptCount,
              reconciledReplayCount >= 0, reconciledReplayCount <= replayReceiptCount,
              contentReconciliationCount >= 0, contentReconciliationCount <= receiptCount,
              completeContentReconciliationCount >= 0,
              completeContentReconciliationCount <= contentReconciliationCount,
              cleanupProofCount == receiptCount,
              isolatedCleanupCount >= 0, isolatedCleanupCount <= cleanupProofCount,
              policyVersion == Self.policyVersion,
              metadataOnly,
              excludesArchiveBytes,
              excludesContentDigests,
              excludesStagingLocator,
              excludesVerifierBuild,
              excludesClientCapability else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

extension DiagnosticExportV1 {
    static func recoverabilityVerificationDiagnosticMetadata(
        receipts: [RecoverabilityVerificationReceiptV1] = [],
        staging: [RecoverabilityVerificationStagingV1] = []
    ) throws -> RecoverabilityVerificationDiagnosticMetadataV1 {
        try RecoverabilityVerificationDiagnosticMetadataV1(
            receipts: receipts,
            staging: staging
        )
    }
}

/// C23 diagnostic health is intentionally aggregate-only. Release, binding,
/// content, locator, license, and subject identifiers are not included.
struct FieldReferenceDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "FIELD_REFERENCE_RELEASE_BINDING_DIAGNOSTIC_V1"
    static let maximumValues = 100_000

    let schemaVersion: Int
    /// Distinct release identities represented by the supplied bindings. A
    /// single immutable release may account for multiple subject bindings.
    let releaseCount: Int
    let bindingCount: Int
    let readyOfflineCount: Int
    let missingBytesCount: Int
    let expiredCount: Int
    let revokedCount: Int
    let supersededCount: Int
    let staleBindingCount: Int
    let protectedDataUnavailableCount: Int
    let unavailableCount: Int
    let availabilityStates: [FieldReferenceAvailabilityV1]
    let policyVersion: String
    let metadataOnly: Bool
    let excludesReferenceBytes: Bool
    let excludesContentIDs: Bool
    let excludesPrivateLocators: Bool
    let excludesLicenseSecrets: Bool
    let excludesSubjectIdentity: Bool

    init(projections: [FieldReferenceReportProjectionV1]) throws {
        guard projections.count <= Self.maximumValues else {
            throw DiagnosticExportError.invalidValue
        }
        try projections.forEach { try $0.validate() }
        let availabilities = projections.map(\.availability)
        let releaseIDs = Set(projections.map(\.releaseID))
        schemaVersion = Self.schemaVersion
        releaseCount = releaseIDs.count
        bindingCount = projections.count
        readyOfflineCount = availabilities.filter { $0 == .readyOffline }.count
        missingBytesCount = availabilities.filter { $0 == .missingBytes }.count
        expiredCount = availabilities.filter { $0 == .expired }.count
        revokedCount = availabilities.filter { $0 == .revoked }.count
        supersededCount = availabilities.filter { $0 == .superseded }.count
        staleBindingCount = availabilities.filter { $0 == .staleBinding }.count
        protectedDataUnavailableCount = availabilities.filter {
            $0 == .protectedDataUnavailable
        }.count
        unavailableCount = availabilities.filter { $0 == .unavailable }.count
        availabilityStates = Array(Set(availabilities)).sorted { $0.rawValue < $1.rawValue }
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesReferenceBytes = true
        excludesContentIDs = true
        excludesPrivateLocators = true
        excludesLicenseSecrets = true
        excludesSubjectIdentity = true
        try validate()
    }

    var isValid: Bool { (try? validate()) != nil }

    func validate() throws {
        let availabilityCounts = [
            readyOfflineCount, missingBytesCount, expiredCount,
            revokedCount, supersededCount, staleBindingCount,
            protectedDataUnavailableCount, unavailableCount,
        ]
        guard availabilityCounts.allSatisfy({
            $0 >= 0 && $0 <= Self.maximumValues
        }) else {
            throw DiagnosticExportError.invalidValue
        }
        let total = availabilityCounts.reduce(0, +)
        guard schemaVersion == Self.schemaVersion,
              releaseCount >= 0, releaseCount <= Self.maximumValues,
              bindingCount >= 0, bindingCount <= Self.maximumValues,
              bindingCount >= releaseCount,
              (bindingCount == 0 || releaseCount > 0),
              total == bindingCount,
              availabilityStates == availabilityStates.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(availabilityStates).count == availabilityStates.count,
              policyVersion == Self.policyVersion,
              metadataOnly,
              excludesReferenceBytes,
              excludesContentIDs,
              excludesPrivateLocators,
              excludesLicenseSecrets,
              excludesSubjectIdentity else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

extension DiagnosticExportV1 {
    static func fieldReferenceDiagnosticMetadata(
        projections: [FieldReferenceReportProjectionV1]
    ) throws -> FieldReferenceDiagnosticMetadataV1 {
        try FieldReferenceDiagnosticMetadataV1(projections: projections)
    }
}

// MARK: - C24 accessible-document diagnostic metadata

/// Aggregate-only C24 health metadata.  This value intentionally contains
/// no semantic node text or IDs, evidence IDs/digests, locators, original
/// bytes, or assessor identity.
struct AccessibleDocumentDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "ACCESSIBLE_DOCUMENT_SEMANTIC_DIAGNOSTIC_V1"
    static let maximumValues = 100_000

    let schemaVersion: Int
    let treeCount: Int
    let customerSafeTreeCount: Int
    let nodeCount: Int
    let documentNodeCount: Int
    let sectionNodeCount: Int
    let headingNodeCount: Int
    let paragraphNodeCount: Int
    let listNodeCount: Int
    let listItemNodeCount: Int
    let tableNodeCount: Int
    let tableRowCount: Int
    let tableHeaderCount: Int
    let tableCellCount: Int
    let figureCount: Int
    let evidenceLinkNodeCount: Int
    let noteNodeCount: Int
    let decorativeFigureCount: Int
    let describedFigureCount: Int
    let missingAlternateTextFigureCount: Int
    let assessmentCount: Int
    let internalPassCount: Int
    let internalFailCount: Int
    let incompleteCount: Int
    let externallyProvedCount: Int
    let assessmentStates: [AccessibleDocumentAssessmentStateV1]
    let policyVersion: String
    let metadataOnly: Bool
    let excludesOriginalEvidence: Bool
    let excludesPrivateEvidence: Bool
    let excludesAssessorIdentity: Bool
    let excludesPrivateLocators: Bool
    let excludesUnsupportedClaims: Bool

    init(
        trees: [AccessibleDocumentSemanticTreeV1] = [],
        assessments: [AccessibleDocumentAssessmentReceiptV1] = []
    ) throws {
        guard trees.count <= Self.maximumValues,
              assessments.count <= Self.maximumValues else {
            throw DiagnosticExportError.invalidValue
        }
        try trees.forEach {
            try AccessibleDocumentIntegrityBoundaryV1.validateTree($0)
        }
        let treeDigests = trees.map(\.treeSHA256)
        guard Set(treeDigests).count == trees.count else {
            throw DiagnosticExportError.invalidValue
        }
        let treeByDigest = Dictionary(uniqueKeysWithValues: trees.map {
            ($0.treeSHA256, $0)
        })
        for assessment in assessments {
            guard let tree = treeByDigest[assessment.treeSHA256] else {
                throw DiagnosticExportError.invalidValue
            }
            try AccessibleDocumentIntegrityBoundaryV1.validateAssessment(
                assessment,
                for: tree
            )
        }

        let nodes = trees.flatMap { $0.nodes }
        guard nodes.count <= Self.maximumValues,
              nodes.allSatisfy({ $0.evidenceLinks.count <= Self.maximumValues }) else {
            throw DiagnosticExportError.invalidValue
        }
        let roleCounts = Dictionary(grouping: nodes, by: \.role).mapValues { $0.count }
        let figures = nodes.filter { $0.role == .figure }
        let assessmentStates = Array(Set(assessments.map(\.state))).sorted {
            $0.rawValue < $1.rawValue
        }
        schemaVersion = Self.schemaVersion
        treeCount = trees.count
        customerSafeTreeCount = trees.filter { $0.audience == .customerSafe }.count
        nodeCount = nodes.count
        documentNodeCount = roleCounts[.document, default: 0]
        sectionNodeCount = roleCounts[.section, default: 0]
        headingNodeCount = roleCounts[.heading, default: 0]
        paragraphNodeCount = roleCounts[.paragraph, default: 0]
        listNodeCount = roleCounts[.list, default: 0]
        listItemNodeCount = roleCounts[.listItem, default: 0]
        tableNodeCount = roleCounts[.table, default: 0]
        tableRowCount = roleCounts[.tableRow, default: 0]
        tableHeaderCount = roleCounts[.tableHeader, default: 0]
        tableCellCount = roleCounts[.tableCell, default: 0]
        figureCount = figures.count
        evidenceLinkNodeCount = nodes.reduce(0) { $0 + $1.evidenceLinks.count }
        noteNodeCount = roleCounts[.note, default: 0]
        decorativeFigureCount = figures.filter { $0.decorative }.count
        describedFigureCount = figures.filter {
            !$0.decorative && $0.alternateText != nil
        }.count
        missingAlternateTextFigureCount = figures.filter {
            !$0.decorative && $0.alternateTextProvenance == .notProvided
        }.count
        assessmentCount = assessments.count
        internalPassCount = assessments.filter { $0.state == .internalPass }.count
        internalFailCount = assessments.filter { $0.state == .internalFail }.count
        incompleteCount = assessments.filter { $0.state == .incomplete }.count
        externallyProvedCount = assessments.filter {
            $0.state == .externallyProved
        }.count
        self.assessmentStates = assessmentStates
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesOriginalEvidence = true
        excludesPrivateEvidence = true
        excludesAssessorIdentity = true
        excludesPrivateLocators = true
        excludesUnsupportedClaims = true
        try validate()
    }

    var isValid: Bool { (try? validate()) != nil }

    func validate() throws {
        let counts = [
            treeCount, customerSafeTreeCount, nodeCount,
            documentNodeCount, sectionNodeCount, headingNodeCount,
            paragraphNodeCount, listNodeCount, listItemNodeCount,
            tableNodeCount, tableRowCount, tableHeaderCount, tableCellCount,
            figureCount, evidenceLinkNodeCount, noteNodeCount,
            decorativeFigureCount, describedFigureCount,
            missingAlternateTextFigureCount, assessmentCount,
            internalPassCount, internalFailCount, incompleteCount,
            externallyProvedCount,
        ]
        let roleTotal = documentNodeCount + sectionNodeCount + headingNodeCount
            + paragraphNodeCount + listNodeCount + listItemNodeCount
            + tableNodeCount + tableRowCount + tableHeaderCount
            + tableCellCount + figureCount + noteNodeCount
        let assessmentTotal = internalPassCount + internalFailCount
            + incompleteCount + externallyProvedCount
        let expectedAssessmentStates: Set<AccessibleDocumentAssessmentStateV1> = Set([
            internalPassCount > 0 ? AccessibleDocumentAssessmentStateV1.internalPass : nil,
            internalFailCount > 0 ? AccessibleDocumentAssessmentStateV1.internalFail : nil,
            incompleteCount > 0 ? AccessibleDocumentAssessmentStateV1.incomplete : nil,
            externallyProvedCount > 0 ? AccessibleDocumentAssessmentStateV1.externallyProved : nil,
        ].compactMap { $0 })
        guard schemaVersion == Self.schemaVersion,
              counts.allSatisfy({ $0 >= 0 && $0 <= Self.maximumValues }),
              customerSafeTreeCount == treeCount,
              roleTotal == nodeCount,
              decorativeFigureCount + describedFigureCount
                  + missingAlternateTextFigureCount == figureCount,
              assessmentTotal == assessmentCount,
              assessmentStates == assessmentStates.sorted(
                  by: { $0.rawValue < $1.rawValue }
              ),
              Set(assessmentStates).count == assessmentStates.count,
              Set(assessmentStates) == expectedAssessmentStates,
              policyVersion == Self.policyVersion,
              metadataOnly,
              excludesOriginalEvidence,
              excludesPrivateEvidence,
              excludesAssessorIdentity,
              excludesPrivateLocators,
              excludesUnsupportedClaims else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

extension DiagnosticExportV1 {
    static func accessibleDocumentDiagnosticMetadata(
        trees: [AccessibleDocumentSemanticTreeV1] = [],
        assessments: [AccessibleDocumentAssessmentReceiptV1] = []
    ) throws -> AccessibleDocumentDiagnosticMetadataV1 {
        try AccessibleDocumentDiagnosticMetadataV1(
            trees: trees,
            assessments: assessments
        )
    }
}

// MARK: - C27 asset-locator diagnostic metadata

/// Aggregate-only locator health. Lookup keys, external-key hashes, signed
/// payloads, public/private key material, actor identity, and receipt bytes are
/// deliberately absent from this diagnostic value.
struct AssetLocatorDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "ASSET_LOCATOR_DIAGNOSTIC_V1"
    static let maximumValues = 200_000

    let schemaVersion: Int
    let locatorCount: Int
    let activeCount: Int
    let retiredCount: Int
    let revokedCount: Int
    let replacedCount: Int
    let bindingReceiptCount: Int
    let policyVersion: String
    let metadataOnly: Bool
    let excludesLocatorPayload: Bool
    let excludesExternalKeyMaterial: Bool
    let excludesSigningKeyMaterial: Bool
    let excludesRawInput: Bool
    let excludesIdentity: Bool

    init(
        locators: [AssetLocatorV1] = [],
        receipts: [LocatorBindingReceiptV1] = []
    ) throws {
        guard locators.count <= Self.maximumValues,
              receipts.count <= Self.maximumValues else {
            throw DiagnosticExportError.invalidValue
        }
        do {
            try AssetLocatorOrphanCleanupPolicyV1.validate(
                locators: locators,
                receipts: receipts
            )
        } catch {
            throw DiagnosticExportError.invalidValue
        }

        schemaVersion = Self.schemaVersion
        locatorCount = locators.count
        activeCount = locators.filter { $0.state == .active }.count
        retiredCount = locators.filter { $0.state == .retired }.count
        revokedCount = locators.filter { $0.state == .revoked }.count
        replacedCount = locators.filter { $0.state == .replaced }.count
        bindingReceiptCount = receipts.count
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesLocatorPayload = true
        excludesExternalKeyMaterial = true
        excludesSigningKeyMaterial = true
        excludesRawInput = true
        excludesIdentity = true
        try validate()
    }

    var isValid: Bool { (try? validate()) != nil }

    func validate() throws {
        let stateTotal = activeCount + retiredCount + revokedCount + replacedCount
        guard schemaVersion == Self.schemaVersion,
              [locatorCount, activeCount, retiredCount, revokedCount,
               replacedCount, bindingReceiptCount]
                .allSatisfy { (0...Self.maximumValues).contains($0) },
              stateTotal == locatorCount,
              policyVersion == Self.policyVersion,
              metadataOnly,
              excludesLocatorPayload,
              excludesExternalKeyMaterial,
              excludesSigningKeyMaterial,
              excludesRawInput,
              excludesIdentity else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

extension DiagnosticExportV1 {
    static func assetLocatorDiagnosticMetadata(
        locators: [AssetLocatorV1] = [],
        receipts: [LocatorBindingReceiptV1] = []
    ) throws -> AssetLocatorDiagnosticMetadataV1 {
        try AssetLocatorDiagnosticMetadataV1(
            locators: locators,
            receipts: receipts
        )
    }
}

// MARK: - C28 schedule diagnostic metadata

/// Aggregate-only schedule health. Canonical release/history bytes, schedule
/// and occurrence IDs, work references, actor snapshots, and notification
/// identifiers are intentionally excluded from diagnostics.
struct ScheduleDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "SCHEDULE_DIAGNOSTIC_V1"
    static let maximumValues = 200_000

    let schemaVersion: Int
    let definitionReleaseCount: Int
    let activeReleaseCount: Int
    let occurrenceHistoryEventCount: Int
    let dueProjectionEntryCount: Int
    let reminderProjectionEntryCount: Int
    let policyVersion: String
    let metadataOnly: Bool
    let excludesSchedulePayload: Bool
    let excludesOccurrenceIdentity: Bool
    let excludesActorIdentity: Bool
    let excludesNotificationState: Bool

    init(
        definitions: [ScheduleDefinitionReleaseV1] = [],
        history: [OccurrenceHistoryEventV1] = [],
        dueProjectionEntryCount: Int = 0,
        reminderProjectionEntryCount: Int = 0
    ) throws {
        guard definitions.count <= Self.maximumValues,
              history.count <= Self.maximumValues,
              (0...Self.maximumValues).contains(dueProjectionEntryCount),
              (0...Self.maximumValues).contains(reminderProjectionEntryCount) else {
            throw DiagnosticExportError.invalidValue
        }
        do {
            try ScheduleLifecycleClosureV1(
                definitions: definitions,
                history: history
            ).validate()
        } catch {
            throw DiagnosticExportError.invalidValue
        }
        schemaVersion = Self.schemaVersion
        definitionReleaseCount = definitions.count
        activeReleaseCount = definitions.filter { $0.lifecycleState == .active }.count
        occurrenceHistoryEventCount = history.count
        self.dueProjectionEntryCount = dueProjectionEntryCount
        self.reminderProjectionEntryCount = reminderProjectionEntryCount
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesSchedulePayload = true
        excludesOccurrenceIdentity = true
        excludesActorIdentity = true
        excludesNotificationState = true
        try validate()
    }

    var isValid: Bool { (try? validate()) != nil }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              [definitionReleaseCount, activeReleaseCount,
               occurrenceHistoryEventCount, dueProjectionEntryCount,
               reminderProjectionEntryCount]
                .allSatisfy({ (0...Self.maximumValues).contains($0) }),
              activeReleaseCount <= definitionReleaseCount,
              policyVersion == Self.policyVersion,
              metadataOnly,
              excludesSchedulePayload,
              excludesOccurrenceIdentity,
              excludesActorIdentity,
              excludesNotificationState else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

extension DiagnosticExportV1 {
    static func scheduleDiagnosticMetadata(
        definitions: [ScheduleDefinitionReleaseV1] = [],
        history: [OccurrenceHistoryEventV1] = [],
        dueProjectionEntryCount: Int = 0,
        reminderProjectionEntryCount: Int = 0
    ) throws -> ScheduleDiagnosticMetadataV1 {
        try ScheduleDiagnosticMetadataV1(
            definitions: definitions,
            history: history,
            dueProjectionEntryCount: dueProjectionEntryCount,
            reminderProjectionEntryCount: reminderProjectionEntryCount
        )
    }
}
