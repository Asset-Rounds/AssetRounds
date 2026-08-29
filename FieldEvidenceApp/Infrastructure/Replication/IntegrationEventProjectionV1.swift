import Foundation

struct IntegrationEventProjectionV1: Sendable {
    let registry: IntegrationContractRegistryV1
    let limits: IntegrationEventLimitsV1

    init(registry: IntegrationContractRegistryV1, limits: IntegrationEventLimitsV1) throws {
        try registry.validate(limits: limits)
        self.registry = registry
        self.limits = limits
    }

    func project(workspaceID: WorkspaceID, acceptedReceipts: [MutationReceiptV1]) throws -> [IntegrationEventV1] {
        guard acceptedReceipts.count <= ChangeJournalLimitsV1.productionMaximumEntitiesPerCheckpoint else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        let orderedReceipts = acceptedReceipts.sorted {
            if $0.resultingRevision.workspaceRevision != $1.resultingRevision.workspaceRevision {
                return $0.resultingRevision.workspaceRevision < $1.resultingRevision.workspaceRevision
            }
            return $0.identity.stableKey < $1.identity.stableKey
        }
        var seenReceiptIDs = Set<MutationReceiptIdentityV1>()
        var seenWorkspaceRevisions = Set<UInt64>()
        var events: [IntegrationEventV1] = []
        var eventCount = 0
        for receipt in orderedReceipts {
            guard receipt.postImages.count <= limits.maximumEventsPerReplay - eventCount else {
                throw IntegrationEventFailureV1.limitExceeded
            }
            eventCount += receipt.postImages.count
        }
        events.reserveCapacity(eventCount)

        for receipt in orderedReceipts {
            try receipt.validate()
            try Self.validatePackagePromotionReceiptShape(receipt)
            try Self.validateMeasurementIntegrityReceiptShape(receipt)
            try Self.validatePrivacyTransformReceiptShape(receipt)
            try Self.validateClientCapabilityReceiptShape(receipt)
            try Self.validateFieldReferenceReceiptShape(receipt)
            try Self.validateAccessibleDocumentAssessmentReceiptShape(receipt)
            try Self.validateSurveyDefinitionReceiptShape(receipt)
            try Self.validateSurveySessionReceiptShape(receipt)
            try Self.validateAssetLocatorReceiptShape(receipt)
            try Self.validateScheduleReceiptShape(receipt)
            try Self.validatePlanReceiptShape(receipt)
            try Self.validatePlacementPoseReceiptShape(receipt)
            try Self.validateEvidenceContextReceiptShape(receipt)
            guard receipt.identity.workspaceID == workspaceID,
                  receipt.resultingRevision.workspaceID == workspaceID else {
                throw IntegrationEventFailureV1.wrongWorkspace
            }
            guard seenReceiptIDs.insert(receipt.identity).inserted,
                  seenWorkspaceRevisions.insert(receipt.resultingRevision.workspaceRevision).inserted else {
                throw IntegrationEventFailureV1.divergentEvent
            }
            guard receipt.postImages.count <= limits.maximumEventsPerReceipt else {
                throw IntegrationEventFailureV1.limitExceeded
            }
            let receiptSHA256 = try receipt.canonicalSHA256()
            for (ordinal, postImage) in receipt.postImages.enumerated() {
                let subject = try postImage.identity
                let definition = try registry.definition(for: subject.kind)
                let payloadValue = try IntegrationEventPayloadV1(
                    subject: subject,
                    subjectRevision: postImage.revision,
                    subjectSemanticSHA256: postImage.semanticSHA256,
                    commandBodySHA256: receipt.commandBodySHA256,
                    resultSHA256: receipt.resultSHA256
                )
                let payload = try WorkspaceMutationCanonicalV1.data(payloadValue)
                guard payload.count <= definition.maximumPayloadBytes,
                      payload.count <= limits.maximumPayloadBytes else {
                    throw IntegrationEventFailureV1.limitExceeded
                }
                let order = try IntegrationEventOrderV1(
                    sourceWorkspaceRevision: receipt.resultingRevision.workspaceRevision,
                    sourceReplicaID: receipt.identity.replicaID,
                    sourceLocalSequence: receipt.identity.localSequence,
                    payloadOrdinal: ordinal
                )
                events.append(try IntegrationEventV1(
                    definition: definition,
                    receipt: receipt,
                    sourceReceiptSHA256: receiptSHA256,
                    subject: subject,
                    subjectRevision: postImage.revision,
                    order: order,
                    payload: payload,
                    limits: limits
                ))
            }
        }
        return try validateProjectedStream(events, workspaceID: workspaceID)
    }

    static let packagePromotionKinds:Set<WorkspaceEntityKindV1>=[.promotedPackageRelease,.packageSandboxRun,.packagePromotionReceipt,.activePackageRegistryPointer]
    static func validatePackagePromotionReceiptShape(_ receipt:MutationReceiptV1)throws {
        let kinds=try receipt.postImages.map{$0.identity.kind}
        let present=Set(kinds).intersection(packagePromotionKinds)
        guard !present.isEmpty else{return}
        guard receipt.postImages.count==4,Set(kinds)==packagePromotionKinds,
              kinds.count==Set(kinds).count,
              let pointer=receipt.postImages.first(where:{(try? $0.identity.kind) == .activePackageRegistryPointer}),
              pointer.revision>0 else{throw IntegrationEventFailureV1.divergentEvent}
        for image in receipt.postImages {
            let identity=try image.identity
            guard identity.kind != .activePackageRegistryPointer else{continue}
            guard image.revision==1,try image.concurrencyIdentity==identity else{throw IntegrationEventFailureV1.divergentEvent}
        }
        let pointerIdentity=try pointer.identity
        let pointerConcurrency=try pointer.concurrencyIdentity
        if pointer.revision==1 {
            guard pointerConcurrency==pointerIdentity,
                  receipt.expectedRevision.entityRevisions.first(where:{$0.identity==pointerIdentity})?.revision==0 else{throw IntegrationEventFailureV1.divergentEvent}
        } else {
            guard pointerConcurrency != pointerIdentity,
                  receipt.expectedRevision.entityRevisions.first(where:{$0.identity==pointerConcurrency})?.revision==pointer.revision-1 else{throw IntegrationEventFailureV1.divergentEvent}
        }
    }
    func validatePackagePromotionReplay(_ receipts:[MutationReceiptV1])throws{let hasPromotion=try receipts.contains{try !$0.postImages.map{$0.identity.kind}.filter{Self.packagePromotionKinds.contains($0)}.isEmpty};if hasPromotion{try PackageEvolutionIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validatePackagePromotionReceiptShape($0)}}
    static let measurementIntegrityKinds:Set<WorkspaceEntityKindV1>=[.instrumentReference,.calibrationStatusSnapshot,.measurementCapture,.measurementSeries,.measurementQualityAssessment]
    static func validateMeasurementIntegrityReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(measurementIntegrityKinds);guard !present.isEmpty else{return};guard receipt.postImages.count<=128,Set(identities).count==identities.count,identities.allSatisfy({measurementIntegrityKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent};for image in receipt.postImages{let identity=try image.identity,concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1,(expected==0)==(identity==concurrency)else{throw IntegrationEventFailureV1.divergentEvent}}}
    func validateMeasurementIntegrityReplay(_ receipts:[MutationReceiptV1])throws{var hasMeasurement=false;for receipt in receipts{for image in receipt.postImages where Self.measurementIntegrityKinds.contains(try image.identity.kind){hasMeasurement=true}};if hasMeasurement{try MeasurementIntegrityIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateMeasurementIntegrityReceiptShape($0)}}
    static let privacyTransformKinds:Set<WorkspaceEntityKindV1>=[.privacyTransformPolicy,.privacyRegion,.privacyTransformManifest,.privacyReviewReceipt]
    static func validatePrivacyTransformReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(privacyTransformKinds);guard !present.isEmpty else{return};guard Set(identities).count==identities.count,identities.allSatisfy({privacyTransformKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent};for image in receipt.postImages{let identity=try image.identity,concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1,(expected==0)==(identity==concurrency)else{throw IntegrationEventFailureV1.divergentEvent}}}
    func validatePrivacyTransformReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.privacyTransformKinds.contains(try image.identity.kind){found=true}};if found{try PrivacyTransformIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validatePrivacyTransformReceiptShape($0)}}
    static let clientCapabilityKinds:Set<WorkspaceEntityKindV1>=[.clientCapabilityProfile,.clientCapabilityAdmissionDecision,.packageLifecyclePolicy,.packageLifecycleDisposition]
    static func validateClientCapabilityReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(clientCapabilityKinds);guard !present.isEmpty else{return};guard receipt.postImages.count==1,let image=receipt.postImages.first,let identity=identities.first,clientCapabilityKinds.contains(identity.kind)else{throw IntegrationEventFailureV1.divergentEvent};let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1,(expected==0)==(identity==concurrency)else{throw IntegrationEventFailureV1.divergentEvent}}
    func validateClientCapabilityReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.clientCapabilityKinds.contains(try image.identity.kind){found=true}};if found{try ClientCapabilityIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateClientCapabilityReceiptShape($0)}}
    static let fieldReferenceKinds:Set<WorkspaceEntityKindV1>=[.fieldReferenceRelease,.fieldReferenceBinding]
    static let accessibleDocumentAssessmentKinds:Set<WorkspaceEntityKindV1>=[.accessibleDocumentAssessmentReceipt]
    static func validateFieldReferenceReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(fieldReferenceKinds);guard !present.isEmpty else{return};guard receipt.postImages.count==1,let image=receipt.postImages.first,let identity=identities.first,fieldReferenceKinds.contains(identity.kind)else{throw IntegrationEventFailureV1.divergentEvent};let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1,(expected==0)==(identity==concurrency)else{throw IntegrationEventFailureV1.divergentEvent}}
    func validateFieldReferenceReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.fieldReferenceKinds.contains(try image.identity.kind){found=true}};if found{try FieldReferenceIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateFieldReferenceReceiptShape($0)}}
    static func validateAccessibleDocumentAssessmentReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(accessibleDocumentAssessmentKinds);guard !present.isEmpty else{return};guard receipt.postImages.count==1,let image=receipt.postImages.first,let identity=identities.first,accessibleDocumentAssessmentKinds.contains(identity.kind)else{throw IntegrationEventFailureV1.divergentEvent};let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1,(expected==0)==(identity==concurrency)else{throw IntegrationEventFailureV1.divergentEvent}}
    func validateAccessibleDocumentAssessmentReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.accessibleDocumentAssessmentKinds.contains(try image.identity.kind){found=true}};if found{try AccessibleDocumentAssessmentIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateAccessibleDocumentAssessmentReceiptShape($0)}}
    static let surveyDefinitionKinds:Set<WorkspaceEntityKindV1>=[.surveyDefinitionIdentity,.surveyDefinitionRelease]
    static func validateSurveyDefinitionReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(surveyDefinitionKinds);guard !present.isEmpty else{return};guard identities.count==Set(identities).count,identities.count==1||identities.count==2,identities.contains(where:{$0.kind == .surveyDefinitionIdentity}),identities.allSatisfy({surveyDefinitionKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent};for image in receipt.postImages{let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1 else{throw IntegrationEventFailureV1.divergentEvent}}}
    func validateSurveyDefinitionReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.surveyDefinitionKinds.contains(try image.identity.kind){found=true}};if found{try SurveyDefinitionIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateSurveyDefinitionReceiptShape($0)}}
    static let surveySessionKinds:Set<WorkspaceEntityKindV1>=[.surveySession,.factCapture,.provisionalSubject,.subjectPromotionReceipt,.surveyPublicationSnapshot]
    static let assetLocatorKinds:Set<WorkspaceEntityKindV1>=[.assetLocator,.locatorBindingReceipt]
    static func validateSurveySessionReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(surveySessionKinds);guard !present.isEmpty else{return};guard Set(identities).count==identities.count,identities.allSatisfy({surveySessionKinds.contains($0.kind)}),[1,2].contains(identities.count)else{throw IntegrationEventFailureV1.divergentEvent};for image in receipt.postImages{let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1 else{throw IntegrationEventFailureV1.divergentEvent}}}
    func validateSurveySessionReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.surveySessionKinds.contains(try image.identity.kind){found=true}};if found{try SurveySessionIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateSurveySessionReceiptShape($0)}}
    static func validateAssetLocatorReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(assetLocatorKinds);guard !present.isEmpty else{return};guard [2,3].contains(identities.count),Set(identities).count==identities.count,identities.contains(where:{$0.kind == .assetLocator}),identities.contains(where:{$0.kind == .locatorBindingReceipt}),identities.allSatisfy({assetLocatorKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent};for image in receipt.postImages{let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1 else{throw IntegrationEventFailureV1.divergentEvent}}}
    func validateAssetLocatorReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.assetLocatorKinds.contains(try image.identity.kind){found=true}};if found{try AssetLocatorIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateAssetLocatorReceiptShape($0)}}
    static let scheduleKinds:Set<WorkspaceEntityKindV1>=[.scheduleDefinitionRelease,.occurrenceHistoryEvent]
    static func validateScheduleReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(scheduleKinds);guard !present.isEmpty else{return};guard Set(identities).count==identities.count,identities.allSatisfy({scheduleKinds.contains($0.kind)}),identities.count<=ScheduleLimitsV1.maximumGeneratedOccurrences else{throw IntegrationEventFailureV1.divergentEvent};for image in receipt.postImages{let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1 else{throw IntegrationEventFailureV1.divergentEvent}}}
    func validateScheduleReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.scheduleKinds.contains(try image.identity.kind){found=true}};if found{try ScheduleIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateScheduleReceiptShape($0)}}
    static let planKinds:Set<WorkspaceEntityKindV1>=[.planDocument,.planRevision,.planPlacement,.planRebaseReceipt]
    static func validatePlanReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(planKinds);guard !present.isEmpty else{return};guard Set(identities).count==identities.count,identities.allSatisfy({planKinds.contains($0.kind)}),identities.count<=PlanLimitsV1.maximumPlacements+2 else{throw IntegrationEventFailureV1.divergentEvent};for image in receipt.postImages{let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1 else{throw IntegrationEventFailureV1.divergentEvent}}}
    func validatePlanReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.planKinds.contains(try image.identity.kind){found=true}};if found{try PlanIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validatePlanReceiptShape($0)}}
    static let placementPoseKinds:Set<WorkspaceEntityKindV1>=[.assetPoseEvent,.spatialAnchorObservation]
    static func validatePlacementPoseReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(placementPoseKinds);guard !present.isEmpty else{return};guard Set(identities).count==identities.count,identities.allSatisfy({placementPoseKinds.contains($0.kind)}),identities.count<=MutationReceiptV1.maximumPostImageCount else{throw IntegrationEventFailureV1.divergentEvent};for image in receipt.postImages{let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1 else{throw IntegrationEventFailureV1.divergentEvent}}}
    func validatePlacementPoseReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.placementPoseKinds.contains(try image.identity.kind){found=true}};if found{try PlacementPoseIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validatePlacementPoseReceiptShape($0)}}
    static let evidenceContextKinds:Set<WorkspaceEntityKindV1>=[.evidenceContext,.pairedObservationLink]
    static func validateEvidenceContextReceiptShape(_ receipt:MutationReceiptV1)throws{let identities=try receipt.postImages.map{$0.identity};let present=Set(identities.map(\.kind)).intersection(evidenceContextKinds);guard !present.isEmpty else{return};guard identities.count==1,let image=receipt.postImages.first,evidenceContextKinds.contains(try image.identity.kind)else{throw IntegrationEventFailureV1.divergentEvent};let concurrency=try image.concurrencyIdentity;guard let expected=receipt.expectedRevision.entityRevisions.first(where:{$0.identity==concurrency})?.revision,expected<UInt64.max,image.revision==expected+1 else{throw IntegrationEventFailureV1.divergentEvent}}
    func validateEvidenceContextReplay(_ receipts:[MutationReceiptV1])throws{var found=false;for receipt in receipts{for image in receipt.postImages where Self.evidenceContextKinds.contains(try image.identity.kind){found=true}};if found{try EvidenceContextIntegrationContractV1.validate(registry:registry)};try receipts.forEach{try Self.validateEvidenceContextReceiptShape($0)}}

    func validateProjectedStream(_ events: [IntegrationEventV1], workspaceID: WorkspaceID) throws -> [IntegrationEventV1] {
        let ordered = events.sorted { $0.order < $1.order }
        guard events == ordered, Set(events.map(\.eventID)).count == events.count else {
            throw IntegrationEventFailureV1.noncanonicalOrder
        }
        var nextOrdinalByReceipt: [MutationReceiptIdentityV1: Int] = [:]
        for event in events {
            guard event.workspaceID == workspaceID else { throw IntegrationEventFailureV1.wrongWorkspace }
            let definition = try registry.definition(eventKind: event.eventKind, version: event.eventVersion)
            try event.validate(definition: definition, limits: limits)
            let expectedOrdinal = nextOrdinalByReceipt[event.sourceReceiptID] ?? 0
            guard event.order.payloadOrdinal == expectedOrdinal else {
                throw IntegrationEventFailureV1.noncanonicalOrder
            }
            nextOrdinalByReceipt[event.sourceReceiptID] = expectedOrdinal + 1
        }
        return events
    }

    func events(after checkpoint: ProjectionCheckpointV1?, workspaceID: WorkspaceID,
                acceptedReceipts: [MutationReceiptV1]) throws -> [IntegrationEventV1] {
        if let checkpoint { try checkpoint.validateResume(workspaceID: workspaceID, registry: registry) }
        let events = try project(workspaceID: workspaceID, acceptedReceipts: acceptedReceipts)
        guard let checkpoint, let lastOrder = checkpoint.lastOrder else { return events }
        guard let matched = events.first(where: {
            $0.order == lastOrder && $0.eventID == checkpoint.lastEventID && $0.eventSHA256 == checkpoint.lastEventSHA256
        }) else { throw IntegrationEventFailureV1.staleCheckpoint }
        return events.filter { $0.order > matched.order }
    }
}

struct IntegrationEventConsumerResultV1: Codable, Equatable, Hashable, Sendable {
    let acceptedEventIDs: [String]
    let terminalStateSHA256: String
    let checkpoint: ProjectionCheckpointV1
}

/// A provider-free reference consumer. Its only logical effect is a digest of
/// accepted event identities, which makes duplicate/crash/checkpoint behavior
/// testable without introducing an outbox, provider, endpoint, or delivery row.
struct IntegrationEventConformanceConsumerV1: Sendable {
    let consumerID: String
    let consumerVersion: Int

    init(consumerID: String = "assetrounds.local.conformance", consumerVersion: Int = 1) throws {
        guard !consumerID.isEmpty, consumerID.utf8.count <= 128, consumerVersion > 0 else {
            throw IntegrationEventFailureV1.invalidValue
        }
        self.consumerID = consumerID
        self.consumerVersion = consumerVersion
    }

    func consume(workspaceID: WorkspaceID, registry: IntegrationContractRegistryV1,
                 events: [IntegrationEventV1], priorCheckpoint: ProjectionCheckpointV1? = nil) throws -> IntegrationEventConsumerResultV1 {
        if let priorCheckpoint {
            try priorCheckpoint.validateResume(workspaceID: workspaceID, registry: registry)
            guard priorCheckpoint.consumerID == consumerID,
                  priorCheckpoint.consumerVersion == consumerVersion else {
                throw IntegrationEventFailureV1.staleCheckpoint
            }
        }
        var byID: [String: IntegrationEventV1] = [:]
        for event in events {
            let definition = try registry.definition(eventKind: event.eventKind, version: event.eventVersion)
            guard consumerVersion >= definition.minimumCompatibleConsumerVersion else {
                throw IntegrationEventFailureV1.unknownPayloadVersion
            }
            try event.validate(definition: definition, limits: try IntegrationEventLimitsV1())
            guard event.workspaceID == workspaceID else { throw IntegrationEventFailureV1.wrongWorkspace }
            if let priorCheckpoint, let priorOrder = priorCheckpoint.lastOrder, event.order <= priorOrder {
                if event.order == priorOrder,
                   event.eventID == priorCheckpoint.lastEventID,
                   event.eventSHA256 == priorCheckpoint.lastEventSHA256 {
                    continue
                }
                throw IntegrationEventFailureV1.staleCheckpoint
            }
            if let existing = byID[event.eventID], existing.eventSHA256 != event.eventSHA256 {
                throw IntegrationEventFailureV1.divergentEvent
            }
            byID[event.eventID] = event
        }
        let unique = byID.values.sorted { $0.order < $1.order }
        let acceptedIDs = unique.map(\.eventID)
        if unique.isEmpty, let priorCheckpoint {
            return IntegrationEventConsumerResultV1(
                acceptedEventIDs: [],
                terminalStateSHA256: priorCheckpoint.consumerStateSHA256,
                checkpoint: priorCheckpoint
            )
        }
        let priorCount = priorCheckpoint?.consumedEventCount ?? 0
        guard UInt64(unique.count) <= UInt64.max - priorCount else { throw IntegrationEventFailureV1.limitExceeded }
        let totalCount = priorCount + UInt64(unique.count)
        var stateSHA: String
        if let priorCheckpoint, priorCheckpoint.consumedEventCount > 0 {
            stateSHA = priorCheckpoint.consumerStateSHA256
        } else {
            stateSHA = try WorkspaceMutationCanonicalV1.sha256(StateGenesisBasis(
                schemaVersion: 1,
                consumerID: consumerID,
                consumerVersion: consumerVersion,
                workspaceID: workspaceID,
                registrySHA256: registry.registrySHA256
            ))
        }
        for event in unique {
            stateSHA = try WorkspaceMutationCanonicalV1.sha256(StateFoldBasis(
                schemaVersion: 1,
                priorStateSHA256: stateSHA,
                eventID: event.eventID,
                eventSHA256: event.eventSHA256,
                order: event.order
            ))
        }
        let checkpoint = try ProjectionCheckpointV1(
            consumerID: consumerID, consumerVersion: consumerVersion, workspaceID: workspaceID,
            registrySHA256: registry.registrySHA256, lastEvent: unique.last,
            consumedEventCount: totalCount, consumerStateSHA256: stateSHA
        )
        return IntegrationEventConsumerResultV1(
            acceptedEventIDs: acceptedIDs, terminalStateSHA256: stateSHA, checkpoint: checkpoint
        )
    }

    private struct StateGenesisBasis: Codable {
        let schemaVersion: Int
        let consumerID: String
        let consumerVersion: Int
        let workspaceID: WorkspaceID
        let registrySHA256: String
    }

    private struct StateFoldBasis: Codable {
        let schemaVersion: Int
        let priorStateSHA256: String
        let eventID: String
        let eventSHA256: String
        let order: IntegrationEventOrderV1
    }
}

/// Operational storage is explicitly disposable. Implementations must publish
/// an event page and its checkpoint atomically, and deletion/Erase may always
/// remove both without touching canonical workspace state.
protocol IntegrationProjectionOperationalStoreV1: Sendable {
    func checkpoint(consumerID: String, workspaceID: WorkspaceID) async throws -> ProjectionCheckpointV1?
    func replaceDerivedProjection(
        events: [IntegrationEventV1],
        checkpoint: ProjectionCheckpointV1,
        consumerID: String,
        workspaceID: WorkspaceID
    ) async throws
    /// Records the local conformance consumer's disposable logical effects.
    /// Repeating identical event IDs is idempotent; divergent bytes fail.
    func recordDerivedConsumerEffects(
        events: [IntegrationEventV1],
        consumerID: String,
        workspaceID: WorkspaceID
    ) async throws
    func dropDerivedProjection(consumerID: String?, workspaceID: WorkspaceID) async throws
}

extension IntegrationProjectionOperationalStoreV1 {
    func recordDerivedConsumerEffects(
        events: [IntegrationEventV1],
        consumerID: String,
        workspaceID: WorkspaceID
    ) async throws {
        throw IntegrationEventFailureV1.invalidValue
    }
}
