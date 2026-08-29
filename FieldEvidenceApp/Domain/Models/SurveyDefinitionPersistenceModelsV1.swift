import Foundation
enum EvidenceContextSurveyDefinitionBoundaryV1{static let controlExpectationsRemainFrozenDefinitionInputs=true;static let capturedContextHistoryIsSeparate=true}
enum PlacementPoseSurveyDefinitionPersistenceBoundaryV1{static let definitionsOwnAxisRequirementsNotPoseEvents=true}
import SwiftData

enum PlanSurveyDefinitionBindingV1 { static let normalizedPlanPlacementRemainsDefinitionSemantic = true; static let planPlacementIsSeparateHistory = true }

enum SurveyDefinitionPersistenceFailureV1: Error { case corruptRow }

@Model final class SurveyDefinitionIdentityRow {
    @Attribute(.unique) var definitionID: UUID
    var workspaceID: UUID
    var activityKindRawValue: String
    var lifecycleStateRawValue: String
    var currentReleaseID: UUID
    var latestLifecycleEventID: UUID
    var revision: UInt64
    var mutationID: UUID
    var identitySHA256: String
    var canonicalData: Data

    init(_ value: SurveyDefinitionIdentityV1) throws {
        let data = try SurveyDefinitionCanonicalCodecV1.encode(value)
        let decoded = try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionIdentityV1.self, from: data)
        guard decoded == value else { throw SurveyDefinitionPersistenceFailureV1.corruptRow }
        definitionID=value.definitionID;workspaceID=value.workspaceID.rawValue
        activityKindRawValue=value.activityKind.rawValue;lifecycleStateRawValue=value.lifecycleState.rawValue
        currentReleaseID=value.currentRelease.releaseID;latestLifecycleEventID=value.latestLifecycleEventID
        revision=value.revision;mutationID=value.mutationID.rawValue;identitySHA256=value.identitySHA256;canonicalData=data
    }

    func value(currentRelease: SurveyDefinitionReleaseV1, event: SurveyDefinitionLifecycleEventV1) throws -> SurveyDefinitionIdentityV1 {
        let value = try value()
        try value.validate(currentRelease: currentRelease, event: event)
        return value
    }

    /// Intrinsic row decoding is used while rebuilding the journal-only
    /// lifecycle event. Admission must subsequently call the linked overload.
    func value() throws -> SurveyDefinitionIdentityV1 {
        let value = try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionIdentityV1.self, from: canonicalData)
        try value.validateIntrinsic()
        guard value.definitionID==definitionID,value.workspaceID.rawValue==workspaceID,
              value.activityKind.rawValue==activityKindRawValue,value.lifecycleState.rawValue==lifecycleStateRawValue,
              value.currentRelease.releaseID==currentReleaseID,value.latestLifecycleEventID==latestLifecycleEventID,
              value.revision==revision,value.mutationID.rawValue==mutationID,value.identitySHA256==identitySHA256 else {
            throw SurveyDefinitionPersistenceFailureV1.corruptRow
        }
        return value
    }

    func replace(with value: SurveyDefinitionIdentityV1, currentRelease: SurveyDefinitionReleaseV1,
                 event: SurveyDefinitionLifecycleEventV1, expectedRevision: UInt64) throws {
        let priorRevision=revision
        guard priorRevision==expectedRevision,priorRevision<UInt64.max,value.definitionID==definitionID,
              value.workspaceID.rawValue==workspaceID,value.revision==priorRevision+1 else {
            throw SurveyDefinitionPersistenceFailureV1.corruptRow
        }
        try value.validate(currentRelease: currentRelease, event: event)
        activityKindRawValue=value.activityKind.rawValue;lifecycleStateRawValue=value.lifecycleState.rawValue
        currentReleaseID=value.currentRelease.releaseID;latestLifecycleEventID=value.latestLifecycleEventID
        revision=value.revision;mutationID=value.mutationID.rawValue;identitySHA256=value.identitySHA256
        canonicalData=try SurveyDefinitionCanonicalCodecV1.encode(value)
    }
}

@Model final class SurveyDefinitionReleaseRow {
    @Attribute(.unique) var releaseID: UUID
    var workspaceID: UUID
    var definitionID: UUID
    var activityKindRawValue: String
    var ownerPackageID: String
    var revision: UInt64
    var mutationID: UUID
    var releaseSHA256: String
    var canonicalData: Data

    init(_ value: SurveyDefinitionReleaseV1) throws {
        try value.validate()
        releaseID=value.releaseID;workspaceID=value.workspaceID.rawValue;definitionID=value.definitionID
        activityKindRawValue=value.activityKind.rawValue;ownerPackageID=value.ownerPackageID
        revision=value.revision;mutationID=value.mutationID.rawValue;releaseSHA256=value.releaseSHA256
        canonicalData=try SurveyDefinitionCanonicalCodecV1.encode(value)
    }

    func value() throws -> SurveyDefinitionReleaseV1 {
        let value=try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionReleaseV1.self,from:canonicalData)
        try value.validate()
        guard value.releaseID==releaseID,value.workspaceID.rawValue==workspaceID,value.definitionID==definitionID,
              value.activityKind.rawValue==activityKindRawValue,value.ownerPackageID==ownerPackageID,
              value.revision==revision,value.mutationID.rawValue==mutationID,value.releaseSHA256==releaseSHA256 else {
            throw SurveyDefinitionPersistenceFailureV1.corruptRow
        }
        return value
    }
}

// MARK: - C26 exact-release session binding

extension SurveyDefinitionReleaseRow {
    /// Decodes the immutable release only when it is the release pinned by the
    /// session. Persistence never substitutes the current/latest definition.
    func value(
        pinnedBy authority: SurveySessionAuthorityV1,
        packageRelease: InspectionPackageReleaseV1
    ) throws -> SurveyDefinitionReleaseV1 {
        let release = try value()
        try authority.validate(definition: release, packageRelease: packageRelease)
        guard authority.definitionRelease == (try SurveyDefinitionReleaseReferenceV1(release)) else {
            throw SurveyDefinitionPersistenceFailureV1.corruptRow
        }
        return release
    }
}


extension SurveyDefinitionReleaseRow {
    /// Resolves the exact definition release embedded in a C28 schedule. It
    /// deliberately never substitutes the latest release in the definition.
    func value(pinnedBy schedule: ScheduleDefinitionReleaseV1) throws -> SurveyDefinitionReleaseV1 {
        let release = try value()
        guard schedule.workspaceID == release.workspaceID,
              schedule.workDefinition.definitionWorkspaceID == release.workspaceID,
              schedule.workDefinition.definitionRelease == (try SurveyDefinitionReleaseReferenceV1(release)) else {
            throw SurveyDefinitionPersistenceFailureV1.corruptRow
        }
        return release
    }
}

enum LightingSurveyDefinitionReuseV1 { static let definitionReleaseReferencesRemainExact = true; static let lightingAddsNoDefinitionRow = true }

enum C31LightingSurveyDefinitionPersistenceBoundaryV1 {
    static let criteriaAndMeasurementMetadataRemainPackageBound = true
    static let persistenceDoesNotStoreLocalizedLabelsAsTruth = true
    static let unsupportedCriterionReferenceFailsClosed = true
}
