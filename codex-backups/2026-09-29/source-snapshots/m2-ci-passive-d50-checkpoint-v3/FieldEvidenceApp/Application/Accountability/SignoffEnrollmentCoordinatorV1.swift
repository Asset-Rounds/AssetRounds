import Foundation

/// Application-only C43 coordinator.  It creates exactly one existing
/// `appendSignoff` mutation and delegates durable, receipt-first recovery to
/// `PartyAccountabilityCoordinatorV1`; it never opens a second writer path.
@MainActor
final class SignoffEnrollmentCoordinatorV1 {
    private let partyCoordinator: PartyAccountabilityCoordinatorV1
    private let idSource: any ApplicationIDSource

    init(
        partyCoordinator: PartyAccountabilityCoordinatorV1,
        idSource: any ApplicationIDSource
    ) {
        self.partyCoordinator = partyCoordinator
        self.idSource = idSource
    }

    func preview(
        _ request: SignoffEnrollmentRequestV1
    ) throws -> SignoffEnrollmentPlanV1 {
        try request.validate()
        let mutationID: MutationIDV1
        if let suppliedMutationID = request.mutationID {
            mutationID = suppliedMutationID
        } else {
            mutationID = try partyCoordinator.makeMutationID()
        }
        let snapshotID = idSource.makeID()
        try PartyAccountabilityValidationV1.requireID(snapshotID)

        let assertion = try SignoffRoleAssertionV1(
            claimedRole: request.claimedRole,
            claimedRelationship: request.claimedRelationship,
            actor: request.actorSnapshot,
            disclosureRelease: request.disclosure.partyDisclosureRelease()
        )
        let snapshot = try SignoffSnapshotV1(
            snapshotID: snapshotID,
            workspaceID: request.workspaceID,
            purpose: request.manifest.purpose,
            subjectID: request.subjectID,
            subjectRevision: request.subjectRevision,
            disposition: .recordedLocalAssertion,
            method: request.selectedMethod,
            roleAssertion: assertion,
            qualification: nil,
            externalEvidenceID: nil,
            occurredAt: request.occurredAt,
            recordedAt: request.recordedAt,
            supersedesSnapshotID: nil,
            mutationID: mutationID
        )
        try C43SignoffEnrollmentBoundaryV1.validate(snapshot)
        let partyPlan = try partyCoordinator.previewC43SignoffEnrollment(
            mutation: .appendSignoff(snapshot),
            expectedRevision: request.expectedRevision,
            workspaceID: request.workspaceID
        )
        return try SignoffEnrollmentPlanV1(
            request: request,
            snapshotID: snapshotID,
            partyPlan: partyPlan
        )
    }

    func commit(
        _ plan: SignoffEnrollmentPlanV1
    ) throws -> SignoffEnrollmentReceiptV1 {
        try plan.validate()
        let partyReceipt = try partyCoordinator.commitC43SignoffEnrollment(
            plan.partyPlan
        )
        return try SignoffEnrollmentReceiptV1(
            plan: plan,
            partyReceipt: partyReceipt
        )
    }
}
