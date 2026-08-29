import CryptoKit
import Foundation

enum IntegrationEventFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion
    case invalidValue
    case invalidDigest
    case limitExceeded
    case duplicateValue
    case noncanonicalOrder
    case unknownEventKind
    case unknownPayloadVersion
    case visibilityViolation
    case divergentEvent
    case wrongWorkspace
    case staleCheckpoint
}

enum IntegrationEventVisibilityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case publicSafe = "PUBLIC_SAFE"
    case workspaceInternal = "WORKSPACE_INTERNAL"
    case sensitiveRedacted = "SENSITIVE_REDACTED"
}

enum IntegrationEventSensitivityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case publicMetadata = "PUBLIC_METADATA"
    case workspaceData = "WORKSPACE_DATA"
    case sensitiveWorkspaceData = "SENSITIVE_WORKSPACE_DATA"
}

enum IntegrationEventRedactionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case notRequired = "NOT_REQUIRED"
    case identifiersOnly = "IDENTIFIERS_ONLY"
}

enum IntegrationEventOrderingBasisV1: String, CaseIterable, Codable, Hashable, Sendable {
    case acceptedWorkspaceRevisionThenReceiptIdentityThenPayloadOrdinal = "ACCEPTED_WORKSPACE_REVISION_THEN_RECEIPT_IDENTITY_THEN_PAYLOAD_ORDINAL"
}

enum IntegrationEventLifecycleV1: String, CaseIterable, Codable, Hashable, Sendable {
    case derivedDropAndRebuild = "DERIVED_DROP_AND_REBUILD"
}

struct IntegrationEventLimitsV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    static let productionMaximumPayloadBytes = 16_384
    static let productionMaximumEventsPerReceipt = MutationReceiptV1.maximumPostImageCount
    static let productionMaximumEventsPerReplay = 100_000
    static let productionMaximumDefinitions = 256

    let schemaVersion: Int
    let maximumPayloadBytes: Int
    let maximumEventsPerReceipt: Int
    let maximumEventsPerReplay: Int
    let maximumDefinitions: Int

    init(
        maximumPayloadBytes: Int = Self.productionMaximumPayloadBytes,
        maximumEventsPerReceipt: Int = Self.productionMaximumEventsPerReceipt,
        maximumEventsPerReplay: Int = Self.productionMaximumEventsPerReplay,
        maximumDefinitions: Int = Self.productionMaximumDefinitions
    ) throws {
        schemaVersion = Self.schemaVersion
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumEventsPerReceipt = maximumEventsPerReceipt
        self.maximumEventsPerReplay = maximumEventsPerReplay
        self.maximumDefinitions = maximumDefinitions
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              (1...Self.productionMaximumPayloadBytes).contains(maximumPayloadBytes),
              (1...Self.productionMaximumEventsPerReceipt).contains(maximumEventsPerReceipt),
              (1...Self.productionMaximumEventsPerReplay).contains(maximumEventsPerReplay),
              (1...Self.productionMaximumDefinitions).contains(maximumDefinitions) else {
            throw IntegrationEventFailureV1.invalidValue
        }
    }
}

struct IntegrationEventContractDefinitionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let eventKind: String
    let eventVersion: Int
    let sourceEntityKind: WorkspaceEntityKindV1
    let sensitivity: IntegrationEventSensitivityV1
    let emittedVisibility: IntegrationEventVisibilityV1
    let redaction: IntegrationEventRedactionV1
    let replayable: Bool
    let orderingBasis: IntegrationEventOrderingBasisV1
    let lifecycle: IntegrationEventLifecycleV1
    let minimumCompatibleConsumerVersion: Int
    let maximumPayloadBytes: Int

    init(
        eventKind: String,
        eventVersion: Int,
        sourceEntityKind: WorkspaceEntityKindV1,
        sensitivity: IntegrationEventSensitivityV1,
        emittedVisibility: IntegrationEventVisibilityV1,
        redaction: IntegrationEventRedactionV1,
        minimumCompatibleConsumerVersion: Int = 1,
        maximumPayloadBytes: Int = IntegrationEventLimitsV1.productionMaximumPayloadBytes
    ) throws {
        schemaVersion = Self.schemaVersion
        self.eventKind = eventKind
        self.eventVersion = eventVersion
        self.sourceEntityKind = sourceEntityKind
        self.sensitivity = sensitivity
        self.emittedVisibility = emittedVisibility
        self.redaction = redaction
        replayable = true
        orderingBasis = .acceptedWorkspaceRevisionThenReceiptIdentityThenPayloadOrdinal
        lifecycle = .derivedDropAndRebuild
        self.minimumCompatibleConsumerVersion = minimumCompatibleConsumerVersion
        self.maximumPayloadBytes = maximumPayloadBytes
        try validate()
    }

    var stableKey: String { "\(eventKind):\(eventVersion)" }

    func validate() throws {
        let validKind = !eventKind.isEmpty && eventKind.utf8.count <= 128
            && eventKind.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 95 }
        let visibilityValid: Bool
        switch sensitivity {
        case .publicMetadata:
            visibilityValid = emittedVisibility == .publicSafe && redaction == .notRequired
        case .workspaceData:
            visibilityValid = emittedVisibility == .workspaceInternal && redaction == .notRequired
        case .sensitiveWorkspaceData:
            visibilityValid = emittedVisibility == .sensitiveRedacted && redaction == .identifiersOnly
        }
        guard schemaVersion == Self.schemaVersion, validKind, eventVersion > 0,
              minimumCompatibleConsumerVersion > 0,
              (1...IntegrationEventLimitsV1.productionMaximumPayloadBytes).contains(maximumPayloadBytes),
              replayable, orderingBasis == .acceptedWorkspaceRevisionThenReceiptIdentityThenPayloadOrdinal,
              lifecycle == .derivedDropAndRebuild, visibilityValid else {
            throw IntegrationEventFailureV1.invalidValue
        }
    }
}

struct IntegrationContractRegistryV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let releaseID: String
    let definitions: [IntegrationEventContractDefinitionV1]
    let registrySHA256: String

    init(releaseID: String, definitions: [IntegrationEventContractDefinitionV1], limits: IntegrationEventLimitsV1) throws {
        schemaVersion = Self.schemaVersion
        self.releaseID = releaseID
        self.definitions = definitions.sorted { $0.stableKey < $1.stableKey }
        registrySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(schemaVersion: Self.schemaVersion, releaseID: releaseID, definitions: self.definitions)
        )
        try validate(limits: limits)
    }

    func definition(for sourceEntityKind: WorkspaceEntityKindV1) throws -> IntegrationEventContractDefinitionV1 {
        let matches = definitions.filter { $0.sourceEntityKind == sourceEntityKind }
        guard matches.count == 1, let value = matches.first else {
            throw IntegrationEventFailureV1.unknownEventKind
        }
        return value
    }

    func definition(eventKind: String, version: Int) throws -> IntegrationEventContractDefinitionV1 {
        guard let value = definitions.first(where: { $0.eventKind == eventKind && $0.eventVersion == version }) else {
            throw IntegrationEventFailureV1.unknownPayloadVersion
        }
        return value
    }

    func validate(limits: IntegrationEventLimitsV1) throws {
        try limits.validate()
        try definitions.forEach { try $0.validate() }
        let keys = definitions.map(\.stableKey)
        let entityKinds = definitions.map(\.sourceEntityKind)
        guard schemaVersion == Self.schemaVersion,
              !releaseID.isEmpty, releaseID.utf8.count <= 128,
              !definitions.isEmpty, definitions.count <= limits.maximumDefinitions,
              keys == keys.sorted(), Set(keys).count == keys.count,
              Set(entityKinds).count == entityKinds.count,
              definitions.allSatisfy({ $0.maximumPayloadBytes <= limits.maximumPayloadBytes }),
              IntegrationEventValidationV1.isSHA256(registrySHA256),
              registrySHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                DigestBasis(schemaVersion: schemaVersion, releaseID: releaseID, definitions: definitions)
              )) else { throw IntegrationEventFailureV1.invalidDigest }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let releaseID: String
        let definitions: [IntegrationEventContractDefinitionV1]
    }
}

enum PackageEvolutionIntegrationContractV1 {
    static func definitions() throws -> [IntegrationEventContractDefinitionV1] {
        try [
            ("package.promoted_release.v1", WorkspaceEntityKindV1.promotedPackageRelease),
            ("package.sandbox_run.v1", .packageSandboxRun),
            ("package.promotion_receipt.v1", .packagePromotionReceipt),
            ("package.active_pointer.v1", .activePackageRegistryPointer),
        ].map { try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired) }.sorted{$0.stableKey<$1.stableKey}
    }
    static func validate(registry:IntegrationContractRegistryV1)throws{let expected=try definitions();for definition in expected{guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}
}
enum MeasurementIntegrityIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("measurement.instrument_reference.v1",WorkspaceEntityKindV1.instrumentReference),("measurement.calibration_snapshot.v1",.calibrationStatusSnapshot),("measurement.capture.v1",.measurementCapture),("measurement.series.v1",.measurementSeries),("measurement.quality_assessment.v1",.measurementQualityAssessment)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum PrivacyTransformIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("privacy.transform_policy.v1",WorkspaceEntityKindV1.privacyTransformPolicy),("privacy.region.v1",.privacyRegion),("privacy.transform_manifest.v1",.privacyTransformManifest),("privacy.review_receipt.v1",.privacyReviewReceipt)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum ClientCapabilityIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("client.capability_profile.v1",WorkspaceEntityKindV1.clientCapabilityProfile),("client.capability_admission.v1",.clientCapabilityAdmissionDecision),("package.lifecycle_policy.v1",.packageLifecyclePolicy),("package.lifecycle_disposition.v1",.packageLifecycleDisposition)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum FieldReferenceIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("field.reference_release.v1",WorkspaceEntityKindV1.fieldReferenceRelease),("field.reference_binding.v1",.fieldReferenceBinding)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum AccessibleDocumentAssessmentIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{[try IntegrationEventContractDefinitionV1(eventKind:"accessible.document_assessment.v1",eventVersion:1,sourceEntityKind:.accessibleDocumentAssessmentReceipt,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)]}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum SurveyDefinitionIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("survey.definition_identity.v1",WorkspaceEntityKindV1.surveyDefinitionIdentity),("survey.definition_release.v1",.surveyDefinitionRelease)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}

enum SurveySessionIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("survey.session.v1",WorkspaceEntityKindV1.surveySession),("survey.fact_capture.v1",.factCapture),("survey.provisional_subject.v1",.provisionalSubject),("survey.subject_promotion_receipt.v1",.subjectPromotionReceipt),("survey.publication_snapshot.v1",.surveyPublicationSnapshot)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum AssetLocatorIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("asset.locator.v1",WorkspaceEntityKindV1.assetLocator),("asset.locator_binding_receipt.v1",.locatorBindingReceipt)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum ScheduleIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("schedule.definition_release.v1",WorkspaceEntityKindV1.scheduleDefinitionRelease),("schedule.occurrence_history.v1",.occurrenceHistoryEvent)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum PlanIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("plan.document.v1",WorkspaceEntityKindV1.planDocument),("plan.revision.v1",.planRevision),("plan.placement.v1",.planPlacement),("plan.rebase_receipt.v1",.planRebaseReceipt)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum PlacementPoseIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("pose.asset_event.v1",WorkspaceEntityKindV1.assetPoseEvent),("pose.spatial_anchor_observation.v1",.spatialAnchorObservation)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum EvidenceContextIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("evidence.context.v1",WorkspaceEntityKindV1.evidenceContext),("evidence.paired_observation_link.v1",.pairedObservationLink)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}static func validate(registry:IntegrationContractRegistryV1)throws{for definition in try definitions(){guard try registry.definition(for:definition.sourceEntityKind)==definition else{throw IntegrationEventFailureV1.unknownEventKind}}}}
enum LightingIntegrationContractV1{static func definitions()throws->[IntegrationEventContractDefinitionV1]{try[("lighting.system.v1",WorkspaceEntityKindV1.lightingSystem),("lighting.observation.v1",.lightingObservation),("lighting.issue.v1",.lightingIssue),("lighting.measurement_plan.v1",.lightingMeasurementPlan),("lighting.claim_state.v1",.lightingClaimState)].map{try IntegrationEventContractDefinitionV1(eventKind:$0.0,eventVersion:1,sourceEntityKind:$0.1,sensitivity:.workspaceData,emittedVisibility:.workspaceInternal,redaction:.notRequired)}.sorted{$0.stableKey<$1.stableKey}}}

struct IntegrationEventOrderV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let sourceWorkspaceRevision: UInt64
    let sourceReplicaID: ReplicaID
    let sourceLocalSequence: UInt64
    let payloadOrdinal: Int

    init(sourceWorkspaceRevision: UInt64, sourceReplicaID: ReplicaID, sourceLocalSequence: UInt64, payloadOrdinal: Int) throws {
        guard sourceReplicaID.rawValue != UUID.zero,
              sourceWorkspaceRevision > 0, sourceLocalSequence > 0, payloadOrdinal >= 0 else {
            throw IntegrationEventFailureV1.invalidValue
        }
        self.sourceWorkspaceRevision = sourceWorkspaceRevision
        self.sourceReplicaID = sourceReplicaID
        self.sourceLocalSequence = sourceLocalSequence
        self.payloadOrdinal = payloadOrdinal
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.sourceWorkspaceRevision != rhs.sourceWorkspaceRevision {
            return lhs.sourceWorkspaceRevision < rhs.sourceWorkspaceRevision
        }
        let l = lhs.sourceReplicaID.rawValue.uuidString.lowercased()
        let r = rhs.sourceReplicaID.rawValue.uuidString.lowercased()
        if l != r { return l < r }
        if lhs.sourceLocalSequence != rhs.sourceLocalSequence { return lhs.sourceLocalSequence < rhs.sourceLocalSequence }
        return lhs.payloadOrdinal < rhs.payloadOrdinal
    }
}

struct IntegrationEventPayloadV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let subject: WorkspaceEntityIdentityV1
    let subjectRevision: UInt64
    let subjectSemanticSHA256: String
    let commandBodySHA256: String
    let resultSHA256: String

    init(subject: WorkspaceEntityIdentityV1, subjectRevision: UInt64, subjectSemanticSHA256: String, commandBodySHA256: String, resultSHA256: String) throws {
        schemaVersion = Self.schemaVersion
        self.subject = subject
        self.subjectRevision = subjectRevision
        self.subjectSemanticSHA256 = subjectSemanticSHA256
        self.commandBodySHA256 = commandBodySHA256
        self.resultSHA256 = resultSHA256
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, subjectRevision > 0,
              [subjectSemanticSHA256, commandBodySHA256, resultSHA256].allSatisfy(IntegrationEventValidationV1.isSHA256) else {
            throw IntegrationEventFailureV1.invalidValue
        }
    }
}

struct IntegrationEventV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let eventID: String
    let eventKind: String
    let eventVersion: Int
    let workspaceID: WorkspaceID
    let sourceMutationID: MutationIDV1
    let sourceReceiptID: MutationReceiptIdentityV1
    let sourceReceiptSHA256: String
    let sourceWorkspaceRevision: UInt64
    let subject: WorkspaceEntityIdentityV1
    let subjectRevision: UInt64
    let visibility: IntegrationEventVisibilityV1
    let redaction: IntegrationEventRedactionV1
    let occurredAt: Date
    let recordedAt: Date
    let order: IntegrationEventOrderV1
    let payload: Data
    let payloadSHA256: String
    let eventSHA256: String

    init(
        definition: IntegrationEventContractDefinitionV1,
        receipt: MutationReceiptV1,
        sourceReceiptSHA256: String,
        subject: WorkspaceEntityIdentityV1,
        subjectRevision: UInt64,
        order: IntegrationEventOrderV1,
        payload: Data,
        limits: IntegrationEventLimitsV1
    ) throws {
        schemaVersion = Self.schemaVersion
        eventKind = definition.eventKind
        eventVersion = definition.eventVersion
        workspaceID = receipt.identity.workspaceID
        sourceMutationID = receipt.mutationID
        sourceReceiptID = receipt.identity
        self.sourceReceiptSHA256 = sourceReceiptSHA256
        sourceWorkspaceRevision = receipt.resultingRevision.workspaceRevision
        self.subject = subject
        self.subjectRevision = subjectRevision
        visibility = definition.emittedVisibility
        redaction = definition.redaction
        occurredAt = receipt.committedAt
        recordedAt = receipt.committedAt
        self.order = order
        self.payload = payload
        payloadSHA256 = IntegrationEventValidationV1.sha256(payload)
        eventID = try WorkspaceMutationCanonicalV1.sha256(IdentityBasis(
            schemaVersion: Self.schemaVersion, eventKind: eventKind, eventVersion: eventVersion,
            workspaceID: workspaceID, sourceMutationID: sourceMutationID,
            sourceReceiptID: sourceReceiptID, sourceReceiptSHA256: sourceReceiptSHA256,
            subject: subject, subjectRevision: subjectRevision, order: order
        ))
        eventSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, eventID: eventID, eventKind: eventKind,
            eventVersion: eventVersion, workspaceID: workspaceID, sourceMutationID: sourceMutationID,
            sourceReceiptID: sourceReceiptID, sourceReceiptSHA256: sourceReceiptSHA256,
            sourceWorkspaceRevision: sourceWorkspaceRevision, subject: subject,
            subjectRevision: subjectRevision, visibility: visibility, redaction: redaction,
            occurredAt: occurredAt, recordedAt: recordedAt, order: order,
            payloadSHA256: payloadSHA256
        ))
        try validate(definition: definition, limits: limits)
    }

    func validate(definition: IntegrationEventContractDefinitionV1, limits: IntegrationEventLimitsV1) throws {
        try definition.validate(); try limits.validate()
        guard schemaVersion == Self.schemaVersion,
              definition.eventKind == eventKind, definition.eventVersion == eventVersion,
              definition.sourceEntityKind == subject.kind,
              definition.emittedVisibility == visibility, definition.redaction == redaction,
              workspaceID == sourceReceiptID.workspaceID,
              order.sourceWorkspaceRevision == sourceWorkspaceRevision,
              order.sourceReplicaID == sourceReceiptID.replicaID,
              order.sourceLocalSequence == sourceReceiptID.localSequence,
              sourceWorkspaceRevision > 0, subjectRevision > 0,
              occurredAt == recordedAt, occurredAt.timeIntervalSinceReferenceDate.isFinite,
              payload.count <= limits.maximumPayloadBytes,
              payload.count <= definition.maximumPayloadBytes,
              IntegrationEventValidationV1.sha256(payload) == payloadSHA256,
              [eventID, sourceReceiptSHA256, payloadSHA256, eventSHA256].allSatisfy(IntegrationEventValidationV1.isSHA256),
              eventID == (try WorkspaceMutationCanonicalV1.sha256(IdentityBasis(
                schemaVersion: schemaVersion, eventKind: eventKind, eventVersion: eventVersion,
                workspaceID: workspaceID, sourceMutationID: sourceMutationID,
                sourceReceiptID: sourceReceiptID, sourceReceiptSHA256: sourceReceiptSHA256,
                subject: subject, subjectRevision: subjectRevision, order: order
              ))),
              eventSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
                schemaVersion: schemaVersion, eventID: eventID, eventKind: eventKind,
                eventVersion: eventVersion, workspaceID: workspaceID, sourceMutationID: sourceMutationID,
                sourceReceiptID: sourceReceiptID, sourceReceiptSHA256: sourceReceiptSHA256,
                sourceWorkspaceRevision: sourceWorkspaceRevision, subject: subject,
                subjectRevision: subjectRevision, visibility: visibility, redaction: redaction,
                occurredAt: occurredAt, recordedAt: recordedAt, order: order,
                payloadSHA256: payloadSHA256
              ))) else { throw IntegrationEventFailureV1.invalidDigest }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(IntegrationEventPayloadV1.self, from: payload)
        try decoded.validate()
        guard decoded.subject == subject, decoded.subjectRevision == subjectRevision,
              (try WorkspaceMutationCanonicalV1.data(decoded)) == payload else {
            throw IntegrationEventFailureV1.invalidValue
        }
    }

    private struct IdentityBasis: Codable {
        let schemaVersion: Int; let eventKind: String; let eventVersion: Int
        let workspaceID: WorkspaceID; let sourceMutationID: MutationIDV1
        let sourceReceiptID: MutationReceiptIdentityV1; let sourceReceiptSHA256: String
        let subject: WorkspaceEntityIdentityV1; let subjectRevision: UInt64
        let order: IntegrationEventOrderV1
    }
    private struct DigestBasis: Codable {
        let schemaVersion: Int; let eventID: String; let eventKind: String; let eventVersion: Int
        let workspaceID: WorkspaceID; let sourceMutationID: MutationIDV1
        let sourceReceiptID: MutationReceiptIdentityV1; let sourceReceiptSHA256: String
        let sourceWorkspaceRevision: UInt64; let subject: WorkspaceEntityIdentityV1
        let subjectRevision: UInt64; let visibility: IntegrationEventVisibilityV1
        let redaction: IntegrationEventRedactionV1; let occurredAt: Date; let recordedAt: Date
        let order: IntegrationEventOrderV1; let payloadSHA256: String
    }
}

struct ProjectionCheckpointV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let consumerID: String
    let consumerVersion: Int
    let workspaceID: WorkspaceID
    let registrySHA256: String
    let lastOrder: IntegrationEventOrderV1?
    let lastEventID: String?
    let lastEventSHA256: String?
    let consumedEventCount: UInt64
    let consumerStateSHA256: String
    let checkpointSHA256: String

    init(consumerID: String, consumerVersion: Int, workspaceID: WorkspaceID, registrySHA256: String,
         lastEvent: IntegrationEventV1?, consumedEventCount: UInt64, consumerStateSHA256: String) throws {
        schemaVersion = Self.schemaVersion; self.consumerID = consumerID; self.consumerVersion = consumerVersion
        self.workspaceID = workspaceID; self.registrySHA256 = registrySHA256
        lastOrder = lastEvent?.order; lastEventID = lastEvent?.eventID; lastEventSHA256 = lastEvent?.eventSHA256
        self.consumedEventCount = consumedEventCount; self.consumerStateSHA256 = consumerStateSHA256
        checkpointSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, consumerID: consumerID, consumerVersion: consumerVersion,
            workspaceID: workspaceID, registrySHA256: registrySHA256, lastOrder: lastOrder,
            lastEventID: lastEventID, lastEventSHA256: lastEventSHA256,
            consumedEventCount: consumedEventCount, consumerStateSHA256: consumerStateSHA256
        ))
        try validate()
    }

    func validate() throws {
        let cursorAllNil = lastOrder == nil && lastEventID == nil && lastEventSHA256 == nil
        let cursorAllPresent = lastOrder != nil && lastEventID != nil && lastEventSHA256 != nil
        guard schemaVersion == Self.schemaVersion, !consumerID.isEmpty, consumerID.utf8.count <= 128,
              consumerVersion > 0, workspaceID.rawValue != UUID.zero,
              [registrySHA256, consumerStateSHA256, checkpointSHA256].allSatisfy(IntegrationEventValidationV1.isSHA256),
              (cursorAllNil || cursorAllPresent), (consumedEventCount == 0) == cursorAllNil,
              lastEventID.map(IntegrationEventValidationV1.isSHA256) ?? true,
              lastEventSHA256.map(IntegrationEventValidationV1.isSHA256) ?? true,
              checkpointSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
                schemaVersion: schemaVersion, consumerID: consumerID, consumerVersion: consumerVersion,
                workspaceID: workspaceID, registrySHA256: registrySHA256, lastOrder: lastOrder,
                lastEventID: lastEventID, lastEventSHA256: lastEventSHA256,
                consumedEventCount: consumedEventCount, consumerStateSHA256: consumerStateSHA256
              ))) else { throw IntegrationEventFailureV1.invalidDigest }
    }

    func validateResume(workspaceID: WorkspaceID, registry: IntegrationContractRegistryV1) throws {
        try validate()
        guard self.workspaceID == workspaceID else { throw IntegrationEventFailureV1.wrongWorkspace }
        guard registry.registrySHA256 == registrySHA256 else { throw IntegrationEventFailureV1.staleCheckpoint }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let consumerID: String; let consumerVersion: Int
        let workspaceID: WorkspaceID; let registrySHA256: String; let lastOrder: IntegrationEventOrderV1?
        let lastEventID: String?; let lastEventSHA256: String?; let consumedEventCount: UInt64
        let consumerStateSHA256: String
    }
}

enum IntegrationProjectionSchemaV1 {
    static let schemaVersion = 1
    static let persistenceMode = "DERIVED_ONLY"
    static let downgradeDisposition = "DROP_AND_REBUILD"
    static let canonicalBackupIncluded = false
    static let canonicalExportIncluded = false
    static let canonicalReportSource = false
}

enum IntegrationEventCanonicalCodecV1 {
    static func encode(_ value: IntegrationContractRegistryV1, limits: IntegrationEventLimitsV1) throws -> Data {
        try value.validate(limits: limits)
        return try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decodeRegistry(_ data: Data, limits: IntegrationEventLimitsV1) throws -> IntegrationContractRegistryV1 {
        let value = try decoder().decode(IntegrationContractRegistryV1.self, from: data)
        try value.validate(limits: limits)
        guard try WorkspaceMutationCanonicalV1.data(value) == data else { throw IntegrationEventFailureV1.invalidDigest }
        return value
    }

    static func encode(_ value: IntegrationEventV1, registry: IntegrationContractRegistryV1,
                       limits: IntegrationEventLimitsV1) throws -> Data {
        let definition = try registry.definition(eventKind: value.eventKind, version: value.eventVersion)
        try value.validate(definition: definition, limits: limits)
        return try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decodeEvent(_ data: Data, registry: IntegrationContractRegistryV1,
                            limits: IntegrationEventLimitsV1) throws -> IntegrationEventV1 {
        let value = try decoder().decode(IntegrationEventV1.self, from: data)
        let definition = try registry.definition(eventKind: value.eventKind, version: value.eventVersion)
        try value.validate(definition: definition, limits: limits)
        guard try WorkspaceMutationCanonicalV1.data(value) == data else { throw IntegrationEventFailureV1.invalidDigest }
        return value
    }

    static func encode(_ value: ProjectionCheckpointV1) throws -> Data {
        try value.validate()
        return try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decodeCheckpoint(_ data: Data) throws -> ProjectionCheckpointV1 {
        let value = try decoder().decode(ProjectionCheckpointV1.self, from: data)
        try value.validate()
        guard try WorkspaceMutationCanonicalV1.data(value) == data else { throw IntegrationEventFailureV1.invalidDigest }
        return value
    }

    private static func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }
}

enum IntegrationEventValidationV1 {
    static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            ("0"..."9").contains(Character(String($0))) || ("a"..."f").contains(Character(String($0)))
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension UUID {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

enum C31LightingIntegrationEventBoundaryV1 {
    static let eventPayloadsRemainOutsideReportsAndDiagnostics = true
    static let consumerReadsFrozenLightingProjectionOnly = true
    static let sourceBytesActorsAndPrivateLocatorsExcluded = true
    static let unsupportedOperationalClaimsRejected = true

    static func isLightingProjectionConsumerEvent(_ event: IntegrationEventV1) -> Bool {
        event.subject.kind == .lightingSystem
            || event.subject.kind == .lightingObservation
            || event.subject.kind == .lightingIssue
            || event.subject.kind == .lightingMeasurementPlan
            || event.subject.kind == .lightingClaimState
    }
}
