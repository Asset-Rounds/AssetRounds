import Foundation

@testable import FieldEvidenceApp

enum DistributionAssetRoleV1: String, Codable, Equatable, Sendable {
    case controller = "CONTROLLER"
    case zone = "ZONE"
    case sharedComponent = "SHARED_COMPONENT"
}

struct DistributionAssetV1: Codable, Equatable, Sendable {
    let id: UUID
    let role: DistributionAssetRoleV1
    let stableLabel: String
}

struct DistributionRelationshipTypeV1: Codable, Equatable, Sendable {
    let id: UUID
    let stableKey: String
    let maximumDestinationsPerSource: Int
    let maximumSourcesPerDestination: Int
}

struct DistributionRelationshipEdgeV1: Codable, Equatable, Sendable {
    let id: UUID
    let relationshipTypeID: UUID
    let sourceAssetID: UUID
    let destinationAssetID: UUID
    let endpointSequence: Int
}

struct PreventiveMaintenanceScheduleV1: Codable, Equatable, Sendable {
    let id: UUID
    let subjectAssetID: UUID
    let intervalDays: Int
    let timeZoneID: String
    let firstDueDayOrdinal: Int
}

struct PreventiveMaintenanceOccurrenceV1: Codable, Equatable, Sendable {
    let id: UUID
    let scheduleID: UUID
    let subjectAssetID: UUID
    let occurrenceSequence: Int
    let completedDayOrdinal: Int
}

struct DistributionMeasurementPlanV1: Codable, Equatable, Sendable {
    let id: UUID
    let subjectAssetID: UUID
    let requiredUnit: ModelMeasurementUnitV1
    let minimumExactValue: ModelExactQuantityV1
}

struct DistributionMeasurementCaptureV1: Codable, Equatable, Sendable {
    let id: UUID
    let planID: UUID
    let subjectAssetID: UUID
    let exactValue: ModelExactQuantityV1
    let captureSequence: Int
}

enum DistributionMeasurementQualityV1: String, Codable, Equatable, Sendable {
    case accepted = "ACCEPTED"
}

struct DistributionMeasurementQualityAssessmentV1: Codable, Equatable, Sendable {
    let id: UUID
    let captureID: UUID
    let exactValuePreserved: Bool
    let quality: DistributionMeasurementQualityV1
}

enum DistributionClaimDispositionV1: String, Codable, Equatable, Sendable {
    case meetsMinimum = "MEETS_MINIMUM"
}

struct DistributionMeasurementClaimV1: Codable, Equatable, Sendable {
    let id: UUID
    let planID: UUID
    let captureID: UUID
    let qualityAssessmentID: UUID
    let exactComparedValue: ModelExactQuantityV1
    let disposition: DistributionClaimDispositionV1
}

struct ControllerZoneDistributionModelV1: Codable, Equatable, Sendable {
    let controller: DistributionAssetV1
    let zones: [DistributionAssetV1]
    let sharedComponent: DistributionAssetV1
    let relationshipTypes: [DistributionRelationshipTypeV1]
    let relationships: [DistributionRelationshipEdgeV1]
    let maintenanceSchedule: PreventiveMaintenanceScheduleV1
    let maintenanceOccurrence: PreventiveMaintenanceOccurrenceV1
    let measurementPlan: DistributionMeasurementPlanV1
    let measurementCapture: DistributionMeasurementCaptureV1
    let measurementQuality: DistributionMeasurementQualityAssessmentV1
    let measurementClaim: DistributionMeasurementClaimV1

    func validate() throws {
        try measurementPlan.minimumExactValue.validate()
        try measurementCapture.exactValue.validate()
        try measurementClaim.exactComparedValue.validate()
        let assets = [controller] + zones + [sharedComponent]
        let assetIDs = assets.map(\.id)
        let typeIDs = relationshipTypes.map(\.id)
        let edgeIDs = relationships.map(\.id)
        let entityIDs = assetIDs + typeIDs + edgeIDs + [
            maintenanceSchedule.id, maintenanceOccurrence.id, measurementPlan.id,
            measurementCapture.id, measurementQuality.id, measurementClaim.id,
        ]
        guard assets.allSatisfy({
                  $0.id != CrossMarketCanonicalV1.zeroUUID && !$0.stableLabel.isEmpty
              }),
              Set(entityIDs).count == entityIDs.count,
              controller.role == .controller, zones.count == 2,
              zones.allSatisfy({ $0.role == .zone }),
              sharedComponent.role == .sharedComponent,
              relationshipTypes.count == 2, relationships.count == 4,
              Set(typeIDs).count == typeIDs.count,
              relationships.allSatisfy({
                  typeIDs.contains($0.relationshipTypeID)
                    && assetIDs.contains($0.sourceAssetID)
                    && assetIDs.contains($0.destinationAssetID)
                    && $0.sourceAssetID != $0.destinationAssetID
                    && $0.endpointSequence > 0
              }) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }

        for relationshipType in relationshipTypes {
            guard !relationshipType.stableKey.isEmpty,
                  relationshipType.maximumDestinationsPerSource > 0,
                  relationshipType.maximumSourcesPerDestination > 0 else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
            let typedEdges = relationships.filter {
                $0.relationshipTypeID == relationshipType.id
            }
            let sourceCounts = Dictionary(grouping: typedEdges, by: \.sourceAssetID)
                .mapValues { $0.count }
            let destinationCounts = Dictionary(grouping: typedEdges, by: \.destinationAssetID)
                .mapValues { $0.count }
            guard sourceCounts.values.allSatisfy({
                      $0 <= relationshipType.maximumDestinationsPerSource
                  }),
                  destinationCounts.values.allSatisfy({
                      $0 <= relationshipType.maximumSourcesPerDestination
                  }) else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        }

        let controllerType = relationshipTypes.first {
            $0.stableKey == "synthetic.relationship.controller-zone"
        }
        let sharedType = relationshipTypes.first {
            $0.stableKey == "synthetic.relationship.zone-shared-component"
        }
        let controllerEdges = relationships.filter {
            $0.relationshipTypeID == controllerType?.id
        }
        let sharedEdges = relationships.filter { $0.relationshipTypeID == sharedType?.id }
        guard controllerType?.maximumDestinationsPerSource == 2,
              controllerType?.maximumSourcesPerDestination == 1,
              Set(controllerEdges.map(\.sourceAssetID)) == Set([controller.id]),
              Set(controllerEdges.map(\.destinationAssetID)) == Set(zones.map(\.id)),
              sharedType?.maximumDestinationsPerSource == 1,
              sharedType?.maximumSourcesPerDestination == 2,
              Set(sharedEdges.map(\.sourceAssetID)) == Set(zones.map(\.id)),
              Set(sharedEdges.map(\.destinationAssetID)) == Set([sharedComponent.id]),
              maintenanceSchedule.subjectAssetID == sharedComponent.id,
              maintenanceSchedule.intervalDays == 90,
              maintenanceSchedule.timeZoneID == "Etc/UTC",
              maintenanceSchedule.firstDueDayOrdinal > 0,
              maintenanceOccurrence.scheduleID == maintenanceSchedule.id,
              maintenanceOccurrence.subjectAssetID == sharedComponent.id,
              maintenanceOccurrence.occurrenceSequence == 1,
              maintenanceOccurrence.completedDayOrdinal
                == maintenanceSchedule.firstDueDayOrdinal,
              measurementPlan.subjectAssetID == zones[0].id,
              measurementPlan.requiredUnit == .lux,
              measurementPlan.minimumExactValue.unit == .lux,
              measurementCapture.planID == measurementPlan.id,
              measurementCapture.subjectAssetID == measurementPlan.subjectAssetID,
              measurementCapture.exactValue.unit == measurementPlan.requiredUnit,
              measurementCapture.captureSequence == 1,
              measurementQuality.captureID == measurementCapture.id,
              measurementQuality.exactValuePreserved,
              measurementQuality.quality == .accepted,
              measurementClaim.planID == measurementPlan.id,
              measurementClaim.captureID == measurementCapture.id,
              measurementClaim.qualityAssessmentID == measurementQuality.id,
              measurementClaim.exactComparedValue == measurementCapture.exactValue,
              measurementClaim.disposition == .meetsMinimum,
              exactIsAtLeast(measurementClaim.exactComparedValue,
                             measurementPlan.minimumExactValue) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    func semanticEntities() throws -> [ModelSemanticEntityV1] {
        var result: [ModelSemanticEntityV1] = []
        func add<T: Encodable>(_ kind: WorkspaceEntityKindV1, _ id: UUID, _ value: T) throws {
            result.append(.init(kind: kind, id: id,
                                contentSHA256: try CrossMarketCanonicalV1.sha256(value)))
        }
        try add(.asset, controller.id, controller)
        for zone in zones { try add(.asset, zone.id, zone) }
        try add(.asset, sharedComponent.id, sharedComponent)
        for type in relationshipTypes {
            try add(.functionalRelationshipTypeDescriptor, type.id, type)
        }
        for edge in relationships {
            try add(.assetFunctionalRelationshipEvent, edge.id, edge)
        }
        try add(.scheduleDefinitionRelease, maintenanceSchedule.id, maintenanceSchedule)
        try add(.occurrenceHistoryEvent, maintenanceOccurrence.id, maintenanceOccurrence)
        try add(.lightingMeasurementPlan, measurementPlan.id, measurementPlan)
        try add(.measurementCapture, measurementCapture.id, measurementCapture)
        try add(.measurementQualityAssessment, measurementQuality.id, measurementQuality)
        try add(.lightingClaimState, measurementClaim.id, measurementClaim)
        return result.sorted { $0.stableKey < $1.stableKey }
    }

    private func exactIsAtLeast(
        _ left: ModelExactQuantityV1, _ right: ModelExactQuantityV1
    ) -> Bool {
        left.unit == right.unit
            && left.numerator * right.denominator >= right.numerator * left.denominator
    }
}

/// Synthetic and nonshipping; the typed endpoints never enter product persistence.
enum ControllerZoneDistributionArchetypeV1 {
    static let archetypeID = "C42.CONTROLLER_ZONE_DISTRIBUTION.V1"
    static let version = 1
    static let defaultSeed: UInt64 = 0xC042_0002_D157_0001
    static let bounds = ModelRunBoundsV1(
        maximumCases: 64, maximumOperationsPerCase: 64,
        maximumShrinkSteps: 64, maximumScratchBytes: 1_048_576,
        maximumDurationMilliseconds: 5_000
    )

    static func scenario(seed: UInt64 = defaultSeed) throws -> CrossMarketArchetypeScenarioV1 {
        var generator = SeededModelGeneratorV1(seed: seed)
        let controllerID = generator.uuid(), zoneAID = generator.uuid()
        let zoneBID = generator.uuid(), sharedID = generator.uuid()
        let controllerTypeID = generator.uuid(), sharedTypeID = generator.uuid()
        let controllerEdgeAID = generator.uuid(), controllerEdgeBID = generator.uuid()
        let sharedEdgeAID = generator.uuid(), sharedEdgeBID = generator.uuid()
        let scheduleID = generator.uuid(), occurrenceID = generator.uuid()
        let planID = generator.uuid(), captureID = generator.uuid(), qualityID = generator.uuid()
        let claimID = generator.uuid()
        let controller = DistributionAssetV1(
            id: controllerID, role: .controller, stableLabel: "synthetic.controller.primary"
        )
        let zones = [
            DistributionAssetV1(id: zoneAID, role: .zone,
                                stableLabel: "synthetic.zone.alpha"),
            DistributionAssetV1(id: zoneBID, role: .zone,
                                stableLabel: "synthetic.zone.beta"),
        ]
        let shared = DistributionAssetV1(
            id: sharedID, role: .sharedComponent,
            stableLabel: "synthetic.component.shared"
        )
        let relationshipTypes = [
            DistributionRelationshipTypeV1(
                id: controllerTypeID,
                stableKey: "synthetic.relationship.controller-zone",
                maximumDestinationsPerSource: 2, maximumSourcesPerDestination: 1
            ),
            DistributionRelationshipTypeV1(
                id: sharedTypeID,
                stableKey: "synthetic.relationship.zone-shared-component",
                maximumDestinationsPerSource: 1, maximumSourcesPerDestination: 2
            ),
        ].sorted { $0.id.uuidString < $1.id.uuidString }
        let relationships = [
            DistributionRelationshipEdgeV1(
                id: controllerEdgeAID, relationshipTypeID: controllerTypeID,
                sourceAssetID: controllerID, destinationAssetID: zoneAID, endpointSequence: 1
            ),
            DistributionRelationshipEdgeV1(
                id: controllerEdgeBID, relationshipTypeID: controllerTypeID,
                sourceAssetID: controllerID, destinationAssetID: zoneBID, endpointSequence: 2
            ),
            DistributionRelationshipEdgeV1(
                id: sharedEdgeAID, relationshipTypeID: sharedTypeID,
                sourceAssetID: zoneAID, destinationAssetID: sharedID, endpointSequence: 1
            ),
            DistributionRelationshipEdgeV1(
                id: sharedEdgeBID, relationshipTypeID: sharedTypeID,
                sourceAssetID: zoneBID, destinationAssetID: sharedID, endpointSequence: 2
            ),
        ].sorted { $0.id.uuidString < $1.id.uuidString }
        let model = try ControllerZoneDistributionModelV1(
            controller: controller, zones: zones, sharedComponent: shared,
            relationshipTypes: relationshipTypes, relationships: relationships,
            maintenanceSchedule: .init(
                id: scheduleID, subjectAssetID: sharedID, intervalDays: 90,
                timeZoneID: "Etc/UTC", firstDueDayOrdinal: 20_000
            ),
            maintenanceOccurrence: .init(
                id: occurrenceID, scheduleID: scheduleID, subjectAssetID: sharedID,
                occurrenceSequence: 1, completedDayOrdinal: 20_000
            ),
            measurementPlan: .init(
                id: planID, subjectAssetID: zoneAID, requiredUnit: .lux,
                minimumExactValue: ModelExactQuantityV1(
                    numerator: 1_000, denominator: 1, unit: .lux
                )
            ),
            measurementCapture: .init(
                id: captureID, planID: planID, subjectAssetID: zoneAID,
                exactValue: ModelExactQuantityV1(
                    numerator: 1_250, denominator: 1, unit: .lux
                ), captureSequence: 1
            ),
            measurementQuality: .init(
                id: qualityID, captureID: captureID,
                exactValuePreserved: true, quality: .accepted
            ),
            measurementClaim: .init(
                id: claimID, planID: planID, captureID: captureID,
                qualityAssessmentID: qualityID,
                exactComparedValue: ModelExactQuantityV1(
                    numerator: 1_250, denominator: 1, unit: .lux
                ), disposition: .meetsMinimum
            )
        )
        try model.validate()

        var operations: [ModelOperationV1] = []
        func append(_ kind: WorkspaceEntityKindV1, _ id: UUID) throws {
            operations.append(try CrossMarketScenarioFactoryV1.operation(
                operations.count + 1, .append, generator: &generator,
                entityKind: kind, entityID: id, expectedRevision: 0, resultingRevision: 1
            ))
        }
        try append(.asset, controllerID)
        for zone in zones { try append(.asset, zone.id) }
        try append(.asset, sharedID)
        for type in relationshipTypes {
            try append(.functionalRelationshipTypeDescriptor, type.id)
        }
        for edge in relationships { try append(.assetFunctionalRelationshipEvent, edge.id) }
        try append(.scheduleDefinitionRelease, scheduleID)
        try append(.occurrenceHistoryEvent, occurrenceID)
        try append(.lightingMeasurementPlan, planID); try append(.measurementCapture, captureID)
        try append(.measurementQualityAssessment, qualityID); try append(.lightingClaimState, claimID)
        operations.append(try CrossMarketScenarioFactoryV1.operation(
            operations.count + 1, .supersede, generator: &generator,
            entityKind: .occurrenceHistoryEvent, entityID: occurrenceID,
            expectedRevision: 1, resultingRevision: 2
        ))
        operations.append(try CrossMarketScenarioFactoryV1.operation(
            operations.count + 1, .rejectStaleRevision, generator: &generator,
            entityKind: .occurrenceHistoryEvent, entityID: occurrenceID,
            expectedRevision: 1, disposition: .rejectedPrecondition
        ))
        for kind in [ModelOperationKindV1.canonicalRoundTrip, .backupRestore,
                     .interruptAfterEffectBeforeReceipt, .replay, .rebuildProjection,
                     .deleteErase, .verifyReleaseExclusion] {
            let disposition: ModelExpectedDispositionV1
            switch kind {
            case .interruptAfterEffectBeforeReceipt: disposition = .interruptedRecoverableEffect
            case .replay: disposition = .idempotentReplay
            default: disposition = .accepted
            }
            operations.append(try CrossMarketScenarioFactoryV1.operation(
                operations.count + 1, kind, generator: &generator, disposition: disposition
            ))
        }
        let scenario = CrossMarketArchetypeScenarioV1(
            archetypeID: archetypeID, archetypeVersion: version, seed: seed,
            bounds: bounds, operations: operations,
            semanticState: .controllerZoneDistribution(model),
            capabilities: [.boundedCardinality, .controllerZoneTopology, .exactMeasurement,
                           .preventiveMaintenance, .sharedComponent],
            expectedInvariants: [.boundedExecution, .canonicalBytesStable, .immutableHistory,
                                 .noScratchOrphan, .oneWriterReceipt, .releaseExcluded,
                                 .replayConverges]
        )
        try scenario.validate()
        return scenario
    }

    static func run(seed: UInt64 = defaultSeed) throws -> ModelRunReceiptV1 {
        try ModelConformanceRunnerV1.run(scenario(seed: seed), expectedInvariant: .boundedExecution)
    }
}
