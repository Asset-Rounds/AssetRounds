import Foundation

@testable import FieldEvidenceApp

struct CompositeSiteV1: Codable, Equatable, Sendable {
    let id: UUID
    let stableLabel: String
}

struct CompositeLocationV1: Codable, Equatable, Sendable {
    let id: UUID
    let siteID: UUID
    let stableLabel: String
}

struct CompositeAreaSubjectV1: Codable, Equatable, Sendable {
    let id: UUID
    let siteID: UUID
    let parentLocationID: UUID
    let exactArea: ModelExactQuantityV1
}

struct CompositeAssetV1: Codable, Equatable, Sendable {
    let id: UUID
    let siteID: UUID
    let areaID: UUID
    let stableLabel: String
}

struct CompositeCompositionV1: Codable, Equatable, Sendable {
    let id: UUID
    let siteID: UUID
    let locationID: UUID
    let areaID: UUID
    let subjectAssetID: UUID
    let componentIndex: Int
}

enum CompositeCriterionDispositionV1: String, Codable, Equatable, Hashable, Sendable {
    case acceptable = "ACCEPTABLE"
    case requiresAction = "REQUIRES_ACTION"
}

struct CompositeCriterionV1: Codable, Equatable, Sendable {
    let id: UUID
    let subjectAreaID: UUID
    let maximumExactValue: ModelExactQuantityV1
    let dispositionAboveMaximum: CompositeCriterionDispositionV1
}

enum CompositeCriterionConflictResolutionV1: String, Codable, Equatable, Sendable {
    case moreRestrictive = "MORE_RESTRICTIVE"
}

struct CompositeCriterionConflictV1: Codable, Equatable, Sendable {
    let id: UUID
    let subjectAreaID: UUID
    let criterionIDs: [UUID]
    let selectedCriterionID: UUID
    let resolution: CompositeCriterionConflictResolutionV1
}

struct CompositeFindingV1: Codable, Equatable, Sendable {
    let id: UUID
    let compositionID: UUID
    let areaID: UUID
    let criterionConflictID: UUID
    let selectedCriterionID: UUID
    let observedExactValue: ModelExactQuantityV1
    let disposition: CompositeCriterionDispositionV1
}

struct CompositeRepairV1: Codable, Equatable, Sendable {
    let id: UUID
    let findingID: UUID
    let repairedCompositionID: UUID
    let completedSequence: Int
}

enum CompositeRecheckOutcomeV1: String, Codable, Equatable, Sendable {
    case resolved = "RESOLVED"
}

struct CompositeRecheckV1: Codable, Equatable, Sendable {
    let id: UUID
    let findingID: UUID
    let repairID: UUID
    let exactValue: ModelExactQuantityV1
    let outcome: CompositeRecheckOutcomeV1
}

struct CompositeActorSnapshotV1: Codable, Equatable, Sendable {
    let id: UUID
    let stableRoleKey: String
    let active: Bool
}

struct CompositeSignoffV1: Codable, Equatable, Sendable {
    let id: UUID
    let recheckID: UUID
    let actorSnapshotID: UUID
    let accepted: Bool
}

struct CompositeReportProjectionV1: Codable, Equatable, Sendable {
    let id: UUID
    let siteID: UUID
    let findingID: UUID
    let repairID: UUID
    let recheckID: UUID
    let signoffID: UUID
    let projectedEntityIDs: [UUID]
}

struct CompositeAreaSafetyModelV1: Codable, Equatable, Sendable {
    let site: CompositeSiteV1
    let location: CompositeLocationV1
    let area: CompositeAreaSubjectV1
    let asset: CompositeAssetV1
    let composition: CompositeCompositionV1
    let criteria: [CompositeCriterionV1]
    let criterionConflict: CompositeCriterionConflictV1
    let finding: CompositeFindingV1
    let repair: CompositeRepairV1
    let recheck: CompositeRecheckV1
    let actorSnapshot: CompositeActorSnapshotV1
    let signoff: CompositeSignoffV1
    let report: CompositeReportProjectionV1

    func validate() throws {
        try area.exactArea.validate()
        try criteria.forEach { try $0.maximumExactValue.validate() }
        try finding.observedExactValue.validate()
        try recheck.exactValue.validate()
        let criterionIDs = criteria.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let entityIDs = [site.id, location.id, area.id, asset.id, composition.id]
            + criterionIDs
            + [criterionConflict.id, finding.id, repair.id, recheck.id,
               actorSnapshot.id, signoff.id, report.id]
        let projectedIDs = [site.id, location.id, area.id, asset.id, composition.id,
                            finding.id, repair.id, recheck.id, actorSnapshot.id, signoff.id]
            .sorted { $0.uuidString < $1.uuidString }
        let evaluatedCriteria = Dictionary(uniqueKeysWithValues: criteria.map {
            ($0.id, disposition(for: finding.observedExactValue, criterion: $0))
        })
        guard entityIDs.allSatisfy({ $0 != CrossMarketCanonicalV1.zeroUUID }),
              Set(entityIDs).count == entityIDs.count,
              !site.stableLabel.isEmpty, !location.stableLabel.isEmpty,
              !asset.stableLabel.isEmpty, criteria.count == 2,
              location.siteID == site.id,
              area.siteID == site.id, area.parentLocationID == location.id,
              area.exactArea.unit == .squareMillimetres,
              asset.siteID == site.id, asset.areaID == area.id,
              composition.siteID == site.id, composition.locationID == location.id,
              composition.areaID == area.id, composition.subjectAssetID == asset.id,
              composition.componentIndex == 0,
              criteria.allSatisfy({
                  $0.subjectAreaID == area.id
                    && $0.maximumExactValue.unit == .squareMillimetres
                    && $0.dispositionAboveMaximum == .requiresAction
              }),
              criterionConflict.subjectAreaID == area.id,
              criterionConflict.criterionIDs == criterionIDs,
              criterionIDs.contains(criterionConflict.selectedCriterionID),
              criterionConflict.resolution == .moreRestrictive,
              Set(evaluatedCriteria.values) == Set([
                  CompositeCriterionDispositionV1.acceptable, .requiresAction,
              ]),
              finding.compositionID == composition.id, finding.areaID == area.id,
              finding.criterionConflictID == criterionConflict.id,
              finding.selectedCriterionID == criterionConflict.selectedCriterionID,
              finding.disposition == .requiresAction,
              evaluatedCriteria[finding.selectedCriterionID] == finding.disposition,
              repair.findingID == finding.id,
              repair.repairedCompositionID == composition.id,
              repair.completedSequence == 1,
              recheck.findingID == finding.id, recheck.repairID == repair.id,
              recheck.outcome == .resolved,
              criteria.first(where: { $0.id == finding.selectedCriterionID }).map {
                  disposition(for: recheck.exactValue, criterion: $0) == .acceptable
              } == true,
              signoff.recheckID == recheck.id,
              actorSnapshot.id != CrossMarketCanonicalV1.zeroUUID,
              !actorSnapshot.stableRoleKey.isEmpty, actorSnapshot.active,
              signoff.actorSnapshotID == actorSnapshot.id,
              signoff.accepted,
              report.siteID == site.id, report.findingID == finding.id,
              report.repairID == repair.id, report.recheckID == recheck.id,
              report.signoffID == signoff.id,
              report.projectedEntityIDs == projectedIDs else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    func semanticEntities() throws -> [ModelSemanticEntityV1] {
        var result: [ModelSemanticEntityV1] = []
        func add<T: Encodable>(_ kind: WorkspaceEntityKindV1, _ id: UUID, _ value: T) throws {
            result.append(.init(kind: kind, id: id,
                                contentSHA256: try CrossMarketCanonicalV1.sha256(value)))
        }
        try add(.site, site.id, site)
        try add(.locationNode, location.id, location)
        try add(.locationNode, area.id, area)
        try add(.asset, asset.id, asset)
        try add(.assetCompositionEvent, composition.id, composition)
        for criterion in criteria {
            try add(.requirementBasisBinding, criterion.id, criterion)
        }
        try add(.findingClassificationBinding, finding.id, finding)
        try add(.correctiveActionEvent, repair.id, repair)
        try add(.inspectionReviewTransition, recheck.id, recheck)
        try add(.actorSnapshot, actorSnapshot.id, actorSnapshot)
        try add(.signoffSnapshot, signoff.id, signoff)
        try add(.report, report.id, report)
        return result.sorted { $0.stableKey < $1.stableKey }
    }

    private func disposition(
        for value: ModelExactQuantityV1, criterion: CompositeCriterionV1
    ) -> CompositeCriterionDispositionV1 {
        guard value.unit == criterion.maximumExactValue.unit else { return .requiresAction }
        let isAbove = value.numerator * criterion.maximumExactValue.denominator
            > criterion.maximumExactValue.numerator * value.denominator
        return isAbove ? criterion.dispositionAboveMaximum : .acceptable
    }
}

/// Synthetic and nonshipping; all identifiers and values are generated locally.
enum CompositeAreaSafetyArchetypeV1 {
    static let archetypeID = "C42.COMPOSITE_AREA_SAFETY.V1"
    static let version = 1
    static let defaultSeed: UInt64 = 0xC042_0001_5AFE_0001
    static let bounds = ModelRunBoundsV1(
        maximumCases: 64, maximumOperationsPerCase: 64,
        maximumShrinkSteps: 64, maximumScratchBytes: 1_048_576,
        maximumDurationMilliseconds: 5_000
    )

    static func scenario(seed: UInt64 = defaultSeed) throws -> CrossMarketArchetypeScenarioV1 {
        var generator = SeededModelGeneratorV1(seed: seed)
        let siteID = generator.uuid(), locationID = generator.uuid(), areaID = generator.uuid()
        let assetID = generator.uuid(), compositionID = generator.uuid()
        let criterionAID = generator.uuid(), criterionBID = generator.uuid()
        let conflictID = generator.uuid(), findingID = generator.uuid(), repairID = generator.uuid()
        let recheckID = generator.uuid(), signoffID = generator.uuid(), actorID = generator.uuid()
        let reportID = generator.uuid()
        let criteria = try [
            CompositeCriterionV1(
                id: criterionAID, subjectAreaID: areaID,
                maximumExactValue: ModelExactQuantityV1(
                    numerator: 1_200_000, denominator: 1, unit: .squareMillimetres
                ), dispositionAboveMaximum: .requiresAction
            ),
            CompositeCriterionV1(
                id: criterionBID, subjectAreaID: areaID,
                maximumExactValue: ModelExactQuantityV1(
                    numerator: 1_000_000, denominator: 1, unit: .squareMillimetres
                ), dispositionAboveMaximum: .requiresAction
            ),
        ].sorted { $0.id.uuidString < $1.id.uuidString }
        let model = try CompositeAreaSafetyModelV1(
            site: .init(id: siteID, stableLabel: "synthetic.site.alpha"),
            location: .init(id: locationID, siteID: siteID,
                            stableLabel: "synthetic.location.primary"),
            area: .init(id: areaID, siteID: siteID, parentLocationID: locationID,
                        exactArea: ModelExactQuantityV1(
                            numerator: 1_100_000, denominator: 1, unit: .squareMillimetres
                        )),
            asset: .init(id: assetID, siteID: siteID, areaID: areaID,
                         stableLabel: "synthetic.asset.composite"),
            composition: .init(id: compositionID, siteID: siteID,
                               locationID: locationID, areaID: areaID,
                               subjectAssetID: assetID, componentIndex: 0),
            criteria: criteria,
            criterionConflict: .init(
                id: conflictID, subjectAreaID: areaID,
                criterionIDs: criteria.map(\.id),
                selectedCriterionID: criterionBID,
                resolution: .moreRestrictive
            ),
            finding: .init(
                id: findingID, compositionID: compositionID, areaID: areaID,
                criterionConflictID: conflictID, selectedCriterionID: criterionBID,
                observedExactValue: ModelExactQuantityV1(
                    numerator: 1_100_000, denominator: 1, unit: .squareMillimetres
                ), disposition: .requiresAction
            ),
            repair: .init(id: repairID, findingID: findingID,
                          repairedCompositionID: compositionID, completedSequence: 1),
            recheck: .init(
                id: recheckID, findingID: findingID, repairID: repairID,
                exactValue: ModelExactQuantityV1(
                    numerator: 900_000, denominator: 1, unit: .squareMillimetres
                ), outcome: .resolved
            ),
            actorSnapshot: .init(
                id: actorID, stableRoleKey: "synthetic.role.reviewer", active: true
            ),
            signoff: .init(id: signoffID, recheckID: recheckID,
                           actorSnapshotID: actorID, accepted: true),
            report: .init(
                id: reportID, siteID: siteID, findingID: findingID,
                repairID: repairID, recheckID: recheckID, signoffID: signoffID,
                projectedEntityIDs: [siteID, locationID, areaID, assetID, compositionID,
                                     findingID, repairID, recheckID, actorID, signoffID]
                    .sorted { $0.uuidString < $1.uuidString }
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
        try append(.site, siteID); try append(.locationNode, locationID)
        try append(.locationNode, areaID); try append(.asset, assetID)
        try append(.assetCompositionEvent, compositionID)
        for criterion in criteria { try append(.requirementBasisBinding, criterion.id) }
        try append(.findingClassificationBinding, findingID)
        try append(.correctiveActionEvent, repairID)
        try append(.inspectionReviewTransition, recheckID)
        try append(.actorSnapshot, actorID)
        try append(.signoffSnapshot, signoffID); try append(.report, reportID)
        operations.append(try CrossMarketScenarioFactoryV1.operation(
            operations.count + 1, .supersede, generator: &generator,
            entityKind: .findingClassificationBinding, entityID: findingID,
            expectedRevision: 1, resultingRevision: 2
        ))
        operations.append(try CrossMarketScenarioFactoryV1.operation(
            operations.count + 1, .rejectStaleRevision, generator: &generator,
            entityKind: .findingClassificationBinding, entityID: findingID,
            expectedRevision: 1, disposition: .rejectedPrecondition
        ))
        for kind in [ModelOperationKindV1.canonicalRoundTrip, .backupRestore, .cloneFork,
                     .interruptBeforeEffect, .interruptAfterEffectBeforeReceipt, .replay,
                     .rebuildProjection, .deleteErase, .verifyReleaseExclusion] {
            let disposition: ModelExpectedDispositionV1
            switch kind {
            case .interruptBeforeEffect: disposition = .interruptedNoEffect
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
            semanticState: .compositeAreaSafety(model),
            capabilities: [.attributionSignoff, .criterionConflict, .findingCorrectiveRecheck,
                           .reportProjection, .siteLocationCompositionArea],
            expectedInvariants: [.boundedExecution, .canonicalBytesStable, .immutableHistory,
                                 .noScratchOrphan, .oneWriterReceipt, .releaseExcluded,
                                 .replayConverges]
        )
        try scenario.validate()
        return scenario
    }

    static func run(seed: UInt64 = defaultSeed) throws -> ModelRunReceiptV1 {
        try ModelConformanceRunnerV1.run(scenario(seed: seed), expectedInvariant: .replayConverges)
    }
}
