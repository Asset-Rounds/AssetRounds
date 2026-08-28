import Foundation
import SwiftData

@MainActor
final class FunctionalRelationshipLifecycleAdapterV1 {
    private let modelContext: ModelContext
    init(modelContext: ModelContext) { self.modelContext = modelContext }

    func projection(
        workspaceID: WorkspaceID,
        boundary: FunctionalRelationshipReadinessBoundaryV1? = nil
    ) throws -> CurrentFunctionalRelationshipProjectionV1 {
        let rawWorkspaceID = workspaceID.rawValue
        let descriptorRows = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(
            predicate: #Predicate { $0.workspaceID == rawWorkspaceID }
        ))
        let eventRows = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(
            predicate: #Predicate { $0.workspaceID == rawWorkspaceID }
        ))
        let descriptors = try descriptorRows.map { try $0.value() }
        let events = try eventRows.map { try $0.value() }
        guard Set(descriptors.map(\.descriptorReleaseID)).count == descriptors.count,
              Set(events.map(\.eventID)).count == events.count else {
            throw FunctionalRelationshipFailureV1.duplicateIdentity
        }
        return try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: workspaceID, events: events, descriptors: descriptors, boundary: boundary
        )
    }

    func preview(
        change: FunctionalRelationshipEndpointChangeV1,
        relationshipID: UUID,
        workspaceID: WorkspaceID,
        currentSiteID: UUID,
        proposedSiteID: UUID? = nil
    ) throws -> FunctionalRelationshipDispositionPreviewV1 {
        let projection = try projection(workspaceID: workspaceID)
        guard let relationship = projection.currentRelationships.first(where: { $0.relationshipID == relationshipID }) else {
            throw FunctionalRelationshipFailureV1.invalidValue
        }
        let descriptorID = relationship.descriptor.descriptorReleaseID
        let rows = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(
            predicate: #Predicate { $0.descriptorReleaseID == descriptorID }
        ))
        guard rows.count == 1, let descriptor = try rows.first?.value(), descriptor.workspaceID == workspaceID else {
            throw FunctionalRelationshipFailureV1.unknownDescriptor
        }
        return try FunctionalRelationshipDispositionPreviewEngineV1.preview(
            change: change, relationship: relationship, descriptor: descriptor,
            currentSiteID: currentSiteID, proposedSiteID: proposedSiteID
        )
    }

    func currentRelationship(relationshipID:UUID,workspaceID:WorkspaceID)throws->AssetFunctionalRelationshipEventV1{let projection=try projection(workspaceID:workspaceID);guard let current=projection.currentRelationships.first(where:{$0.relationshipID==relationshipID})else{throw FunctionalRelationshipFailureV1.invalidValue};let eventID=current.eventID;let rows=try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(predicate:#Predicate{$0.eventID==eventID}));guard rows.count==1,let row=rows.first else{throw FunctionalRelationshipFailureV1.duplicateIdentity};return try row.exactCurrentReference(relationshipID:relationshipID,workspaceID:workspaceID)}
}
