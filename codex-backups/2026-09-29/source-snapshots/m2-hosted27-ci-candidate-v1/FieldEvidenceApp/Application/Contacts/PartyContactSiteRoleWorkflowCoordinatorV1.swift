import Foundation

enum PartyContactSiteRoleWorkflowCommandV1: Equatable, Sendable {
    case commitParty(PartyWorkflowPreviewV1)
    case recoverParty(PartyWorkflowPreviewV1)
    case commitContact(OperationalContactWorkflowPreviewV1)
    case recoverContact(OperationalContactWorkflowPreviewV1)
    case commitSiteRole(SiteRoleWorkflowPreviewV1)
    case recoverSiteRole(SiteRoleWorkflowPreviewV1)
}

enum PartyContactSiteRoleWorkflowOutcomeV1: Equatable, Sendable {
    case party(PartyAccountabilityChangeReceiptV1)
    case contact(OperationalContactMutationReceiptV1)
    case siteRole(PartyAccountabilityChangeReceiptV1)
}

@MainActor
final class PartyContactSiteRoleWorkflowCoordinatorV1 {
    private let partyCoordinator: PartyAccountabilityCoordinatorV1
    private let contactCoordinator: OperationalContactCoordinatorV1
    private let query: any PartyContactSiteRoleWorkflowQueryingV1

    init(
        partyCoordinator: PartyAccountabilityCoordinatorV1,
        contactCoordinator: OperationalContactCoordinatorV1,
        query: any PartyContactSiteRoleWorkflowQueryingV1
    ) {
        self.partyCoordinator = partyCoordinator
        self.contactCoordinator = contactCoordinator
        self.query = query
    }

    func previewCreateParty(
        workspaceID: WorkspaceID,
        partyID: UUID,
        kind: ServicePartyKindV1,
        displayName: String,
        profileDescriptor: String? = nil,
        provenance: ServicePartyProvenanceV1 = .locallyRecorded,
        effectiveAt: Date,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> PartyWorkflowPreviewV1 {
        guard try await query.currentParty(workspaceID: workspaceID, partyID: partyID) == nil else {
            throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch
        }
        let successor = try ServicePartyReferenceV1(
            partyID: partyID,
            workspaceID: workspaceID,
            kind: kind,
            displayName: displayName,
            profileDescriptor: profileDescriptor,
            provenance: provenance,
            state: .effective,
            effectiveAt: effectiveAt,
            revision: 1,
            mutationID: mutationID
        )
        return try partyPreview(
            operation: .createParty,
            mutation: .recordParty(successor),
            expectedRevision: expectedRevision,
            workspaceID: workspaceID,
            partyID: partyID
        )
    }

    func previewEditParty(
        workspaceID: WorkspaceID,
        partyID: UUID,
        displayName: String,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> PartyWorkflowPreviewV1 {
        let predecessor = try await requiredEffectiveParty(
            workspaceID: workspaceID,
            partyID: partyID
        )
        let successor = try ServicePartyReferenceV1(
            partyID: predecessor.partyID,
            workspaceID: predecessor.workspaceID,
            kind: predecessor.kind,
            displayName: displayName,
            profileDescriptor: predecessor.profileDescriptor,
            provenance: predecessor.provenance,
            privacyClass: predecessor.privacyClass,
            state: .effective,
            effectiveAt: predecessor.effectiveAt,
            revision: try increment(predecessor.revision),
            mutationID: mutationID
        )
        try successor.validateSuccessor(of: predecessor)
        return try partyPreview(
            operation: .editParty,
            mutation: .recordParty(successor),
            expectedRevision: expectedRevision,
            workspaceID: workspaceID,
            partyID: partyID
        )
    }

    func previewRetireParty(
        workspaceID: WorkspaceID,
        partyID: UUID,
        retiredAt: Date,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> PartyWorkflowPreviewV1 {
        let predecessor = try await requiredEffectiveParty(
            workspaceID: workspaceID,
            partyID: partyID
        )
        let successor = try ServicePartyReferenceV1(
            partyID: predecessor.partyID,
            workspaceID: predecessor.workspaceID,
            kind: predecessor.kind,
            displayName: predecessor.displayName,
            profileDescriptor: predecessor.profileDescriptor,
            provenance: predecessor.provenance,
            privacyClass: predecessor.privacyClass,
            state: .retired,
            effectiveAt: predecessor.effectiveAt,
            retiredAt: retiredAt,
            revision: try increment(predecessor.revision),
            mutationID: mutationID
        )
        try successor.validateSuccessor(of: predecessor)
        return try partyPreview(
            operation: .retireParty,
            mutation: .recordParty(successor),
            expectedRevision: expectedRevision,
            workspaceID: workspaceID,
            partyID: partyID
        )
    }

    func previewCreateContact(
        workspaceID: WorkspaceID,
        contactPointID: UUID,
        partyID: UUID,
        kind: ServiceContactKindV1,
        label: ServiceContactLabelV1,
        displayValue: String,
        preferred: Bool,
        effectiveAt: Date,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> OperationalContactWorkflowPreviewV1 {
        let party = try await requiredEffectiveParty(workspaceID: workspaceID, partyID: partyID)
        let current = try await currentScope(
            workspaceID: workspaceID,
            party: party,
            kind: kind
        )
        guard !current.contains(where: { $0.contactPointID == contactPointID }) else {
            throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch
        }
        let contact = try ServiceContactPointV1(
            contactPointID: contactPointID,
            workspaceID: workspaceID,
            party: party,
            kind: kind,
            label: label,
            displayValue: displayValue,
            preferred: preferred,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: effectiveAt,
            revision: 1,
            mutationID: mutationID
        )
        return try contactPreview(
            operation: .createContact,
            party: party,
            current: current,
            primaryPredecessor: nil,
            primarySuccessor: contact,
            requestedPreferred: preferred,
            expectedRevision: expectedRevision,
            mutationID: mutationID
        )
    }

    func previewEditContact(
        workspaceID: WorkspaceID,
        contactPointID: UUID,
        label: ServiceContactLabelV1,
        displayValue: String,
        preferred: Bool,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> OperationalContactWorkflowPreviewV1 {
        let predecessor = try await requiredContact(
            workspaceID: workspaceID,
            contactPointID: contactPointID
        )
        guard predecessor.lifecycle == .effective else {
            throw PartyContactSiteRoleWorkflowFailureV1.staleRevision
        }
        let party = try await requiredEffectiveParty(
            workspaceID: workspaceID,
            partyID: predecessor.party.partyID
        )
        try predecessor.validatePartyCompatibility(with: party)
        let current = try await currentScope(
            workspaceID: workspaceID,
            party: party,
            kind: predecessor.kind
        )
        let successor = try contactSuccessor(
            predecessor: predecessor,
            party: party,
            label: label,
            displayValue: displayValue,
            preferred: preferred,
            lifecycle: .effective,
            retiredAt: nil,
            mutationID: mutationID
        )
        return try contactPreview(
            operation: .editContact,
            party: party,
            current: current,
            primaryPredecessor: predecessor,
            primarySuccessor: successor,
            requestedPreferred: preferred,
            expectedRevision: expectedRevision,
            mutationID: mutationID
        )
    }

    func previewRetireContact(
        workspaceID: WorkspaceID,
        contactPointID: UUID,
        retiredAt: Date,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> OperationalContactWorkflowPreviewV1 {
        let predecessor = try await requiredContact(
            workspaceID: workspaceID,
            contactPointID: contactPointID
        )
        guard predecessor.lifecycle == .effective else {
            throw PartyContactSiteRoleWorkflowFailureV1.staleRevision
        }
        let party = try await requiredEffectiveParty(
            workspaceID: workspaceID,
            partyID: predecessor.party.partyID
        )
        let current = try await currentScope(
            workspaceID: workspaceID,
            party: party,
            kind: predecessor.kind
        )
        let successor = try contactSuccessor(
            predecessor: predecessor,
            party: party,
            label: predecessor.label,
            displayValue: predecessor.displayValue,
            preferred: false,
            lifecycle: .retired,
            retiredAt: retiredAt,
            mutationID: mutationID
        )
        return try contactPreview(
            operation: .retireContact,
            party: party,
            current: current,
            primaryPredecessor: predecessor,
            primarySuccessor: successor,
            requestedPreferred: false,
            expectedRevision: expectedRevision,
            mutationID: mutationID
        )
    }

    func previewReactivateContact(
        workspaceID: WorkspaceID,
        contactPointID: UUID,
        preferred: Bool,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> OperationalContactWorkflowPreviewV1 {
        let predecessor = try await requiredContact(
            workspaceID: workspaceID,
            contactPointID: contactPointID
        )
        guard predecessor.lifecycle == .retired else {
            throw PartyContactSiteRoleWorkflowFailureV1.staleRevision
        }
        let party = try await requiredEffectiveParty(
            workspaceID: workspaceID,
            partyID: predecessor.party.partyID
        )
        let current = try await currentScope(
            workspaceID: workspaceID,
            party: party,
            kind: predecessor.kind
        )
        let successor = try contactSuccessor(
            predecessor: predecessor,
            party: party,
            label: predecessor.label,
            displayValue: predecessor.displayValue,
            preferred: preferred,
            lifecycle: .effective,
            retiredAt: nil,
            mutationID: mutationID
        )
        return try contactPreview(
            operation: .reactivateContact,
            party: party,
            current: current,
            primaryPredecessor: predecessor,
            primarySuccessor: successor,
            requestedPreferred: preferred,
            expectedRevision: expectedRevision,
            mutationID: mutationID
        )
    }

    func previewSetPreferredContact(
        workspaceID: WorkspaceID,
        contactPointID: UUID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> OperationalContactWorkflowPreviewV1 {
        let predecessor = try await requiredContact(
            workspaceID: workspaceID,
            contactPointID: contactPointID
        )
        guard predecessor.lifecycle == .effective else {
            throw PartyContactSiteRoleWorkflowFailureV1.staleRevision
        }
        let party = try await requiredEffectiveParty(
            workspaceID: workspaceID,
            partyID: predecessor.party.partyID
        )
        let current = try await currentScope(
            workspaceID: workspaceID,
            party: party,
            kind: predecessor.kind
        )
        let successor = try contactSuccessor(
            predecessor: predecessor,
            party: party,
            label: predecessor.label,
            displayValue: predecessor.displayValue,
            preferred: true,
            lifecycle: .effective,
            retiredAt: nil,
            mutationID: mutationID
        )
        return try contactPreview(
            operation: .setPreferredContact,
            party: party,
            current: current,
            primaryPredecessor: predecessor,
            primarySuccessor: successor,
            requestedPreferred: true,
            expectedRevision: expectedRevision,
            mutationID: mutationID
        )
    }

    func previewAppendSiteRole(
        workspaceID: WorkspaceID,
        eventID: UUID,
        siteID: UUID,
        partyID: UUID,
        role: SitePartyRoleV1,
        effectiveFrom: Date,
        effectiveUntil: Date? = nil,
        recordedAt: Date,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> SiteRoleWorkflowPreviewV1 {
        _ = try await requiredEffectiveParty(workspaceID: workspaceID, partyID: partyID)
        let history = try await query.siteRoleHistory(
            workspaceID: workspaceID,
            siteID: siteID,
            partyID: partyID
        )
        guard !history.contains(where: { $0.eventID == eventID }) else {
            throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch
        }
        let event = try SitePartyRoleEventV1(
            eventID: eventID,
            workspaceID: workspaceID,
            siteID: siteID,
            partyID: partyID,
            role: role,
            effectiveFrom: effectiveFrom,
            effectiveUntil: effectiveUntil,
            source: .locallyRecorded,
            revision: 1,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        return try rolePreview(
            operation: .appendSiteRole,
            event: event,
            predecessor: nil,
            expectedRevision: expectedRevision
        )
    }

    /// Replaces the exact prior role interval with one append-only successor.
    /// Passing nil `effectiveUntil` reverses an earlier close; passing a date
    /// closes or corrects the interval. Site, Party, and role cannot change.
    func previewReverseSiteRole(
        workspaceID: WorkspaceID,
        siteID: UUID,
        predecessorEventID: UUID,
        successorEventID: UUID,
        effectiveFrom: Date,
        effectiveUntil: Date?,
        recordedAt: Date,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> SiteRoleWorkflowPreviewV1 {
        let all = try await query.siteRoleHistory(
            workspaceID: workspaceID,
            siteID: siteID,
            partyID: nil
        )
        guard let predecessor = all.first(where: { $0.eventID == predecessorEventID }),
              predecessor.siteID == siteID,
              !all.contains(where: { $0.eventID == successorEventID }) else {
            throw PartyContactSiteRoleWorkflowFailureV1.invalidReversal
        }
        let successor = try SitePartyRoleEventV1(
            eventID: successorEventID,
            workspaceID: workspaceID,
            siteID: predecessor.siteID,
            partyID: predecessor.partyID,
            role: predecessor.role,
            effectiveFrom: effectiveFrom,
            effectiveUntil: effectiveUntil,
            source: .locallyRecorded,
            supersedesEventID: predecessor.eventID,
            revision: try increment(predecessor.revision),
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        try successor.validateSupersession(of: predecessor)
        return try rolePreview(
            operation: .reverseSiteRole,
            event: successor,
            predecessor: predecessor,
            expectedRevision: expectedRevision
        )
    }

    func history(
        workspaceID: WorkspaceID,
        partyRevisions: [ServicePartyReferenceV1],
        contactRevisions: [ServiceContactPointV1],
        siteRoleEvents: [SitePartyRoleEventV1]
    ) throws -> PartyContactSiteRoleHistoryProjectionV1 {
        try .init(
            workspaceID: workspaceID,
            partyRevisions: partyRevisions,
            contactRevisions: contactRevisions,
            siteRoleEvents: siteRoleEvents
        )
    }

    func execute(
        _ command: PartyContactSiteRoleWorkflowCommandV1
    ) async throws -> PartyContactSiteRoleWorkflowOutcomeV1 {
        switch command {
        case .commitParty(let preview), .recoverParty(let preview):
            guard preview.zeroWrite else { throw PartyContactSiteRoleWorkflowFailureV1.invalidContext }
            return .party(try partyCoordinator.commit(preview.plan))
        case .commitContact(let preview):
            guard preview.zeroWrite else { throw PartyContactSiteRoleWorkflowFailureV1.invalidContext }
            return .contact(try await contactCoordinator.commitManualMutation(preview.mutation))
        case .recoverContact(let preview):
            guard preview.zeroWrite else { throw PartyContactSiteRoleWorkflowFailureV1.invalidContext }
            return .contact(try await contactCoordinator.recoverManualMutation(preview.mutation))
        case .commitSiteRole(let preview), .recoverSiteRole(let preview):
            guard preview.zeroWrite else { throw PartyContactSiteRoleWorkflowFailureV1.invalidContext }
            return .siteRole(try partyCoordinator.commit(preview.plan))
        }
    }

    private func partyPreview(
        operation: PartyContactSiteRoleOperationV1,
        mutation: PartyAccountabilityMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        workspaceID: WorkspaceID,
        partyID: UUID
    ) throws -> PartyWorkflowPreviewV1 {
        let plan = try partyCoordinator.preview(
            mutation: mutation,
            expectedRevision: expectedRevision,
            workspaceID: workspaceID
        )
        return try .init(
            plan: plan,
            impact: .init(operation: operation, affectedPartyIDs: [partyID])
        )
    }

    private func rolePreview(
        operation: PartyContactSiteRoleOperationV1,
        event: SitePartyRoleEventV1,
        predecessor: SitePartyRoleEventV1?,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) throws -> SiteRoleWorkflowPreviewV1 {
        let plan = try partyCoordinator.preview(
            mutation: .appendSiteRole(event),
            expectedRevision: expectedRevision,
            workspaceID: event.workspaceID
        )
        return try .init(
            plan: plan,
            predecessor: predecessor,
            impact: .init(
                operation: operation,
                affectedPartyIDs: [event.partyID],
                affectedSiteRoleEventIDs: [event.eventID]
            )
        )
    }

    private func contactPreview(
        operation: PartyContactSiteRoleOperationV1,
        party: ServicePartyReferenceV1,
        current: [ServiceContactPointV1],
        primaryPredecessor: ServiceContactPointV1?,
        primarySuccessor: ServiceContactPointV1,
        requestedPreferred: Bool,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) throws -> OperationalContactWorkflowPreviewV1 {
        var predecessors: [ServiceContactPointV1] = []
        var successors: [ServiceContactPointV1] = []
        if let primaryPredecessor { predecessors.append(primaryPredecessor) }
        successors.append(primarySuccessor)

        if requestedPreferred {
            for value in current where value.lifecycle == .effective
                && value.preferred && value.contactPointID != primarySuccessor.contactPointID {
                predecessors.append(value)
                successors.append(try contactSuccessor(
                    predecessor: value,
                    party: party,
                    label: value.label,
                    displayValue: value.displayValue,
                    preferred: false,
                    lifecycle: .effective,
                    retiredAt: nil,
                    mutationID: mutationID
                ))
            }
        }
        var final = Dictionary(uniqueKeysWithValues: current.map { ($0.contactPointID, $0) })
        for successor in successors { final[successor.contactPointID] = successor }
        let active = final.values.filter { $0.lifecycle == .effective }.sorted {
            $0.contactPointID.uuidString < $1.contactPointID.uuidString
        }
        let preferred = active.filter(\.preferred)
        guard preferred.count <= 1 else {
            throw PartyContactSiteRoleWorkflowFailureV1.preferredConflict
        }
        let scope = try ServiceContactPreferredScopeV1(
            partyID: party.partyID,
            kind: primarySuccessor.kind,
            activeContactPointIDs: active.map(\.contactPointID),
            preferredContactPointID: preferred.first?.contactPointID
        )
        let mutation = try OperationalContactMutationV1(
            workspaceID: party.workspaceID,
            mutationID: mutationID,
            expectedRevision: expectedRevision,
            predecessors: predecessors,
            successors: successors,
            preferredScopes: [scope]
        )
        return try .init(
            mutation: mutation,
            impact: .init(
                operation: operation,
                affectedPartyIDs: [party.partyID],
                affectedContactPointIDs: successors.map(\.contactPointID),
                preferredScopes: [scope]
            )
        )
    }

    private func currentScope(
        workspaceID: WorkspaceID,
        party: ServicePartyReferenceV1,
        kind: ServiceContactKindV1
    ) async throws -> [ServiceContactPointV1] {
        let values = try await query.currentContactPoints(
            workspaceID: workspaceID,
            partyID: party.partyID,
            kind: kind
        ).sorted { $0.contactPointID.uuidString < $1.contactPointID.uuidString }
        guard Set(values.map(\.contactPointID)).count == values.count else {
            throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch
        }
        try values.forEach {
            guard $0.kind == kind else { throw PartyContactSiteRoleWorkflowFailureV1.invalidContext }
            try $0.validatePartyCompatibility(with: party)
        }
        return values
    }

    private func requiredEffectiveParty(
        workspaceID: WorkspaceID,
        partyID: UUID
    ) async throws -> ServicePartyReferenceV1 {
        guard let value = try await query.currentParty(
            workspaceID: workspaceID,
            partyID: partyID
        ), value.workspaceID == workspaceID, value.partyID == partyID else {
            throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch
        }
        guard value.state == .effective else {
            throw PartyContactSiteRoleWorkflowFailureV1.retiredParty
        }
        return value
    }

    private func requiredContact(
        workspaceID: WorkspaceID,
        contactPointID: UUID
    ) async throws -> ServiceContactPointV1 {
        guard let value = try await contactCoordinator.currentContactPoint(
            workspaceID: workspaceID,
            contactPointID: contactPointID
        ), value.workspaceID == workspaceID, value.contactPointID == contactPointID else {
            throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch
        }
        return value
    }

    private func contactSuccessor(
        predecessor: ServiceContactPointV1,
        party: ServicePartyReferenceV1,
        label: ServiceContactLabelV1,
        displayValue: String,
        preferred: Bool,
        lifecycle: ServiceContactLifecycleV1,
        retiredAt: Date?,
        mutationID: MutationIDV1
    ) throws -> ServiceContactPointV1 {
        try predecessor.validatePartyCompatibility(with: party)
        guard predecessor.provenance == .manual else {
            throw PartyContactSiteRoleWorkflowFailureV1.invalidContext
        }
        return try ServiceContactPointV1(
            contactPointID: predecessor.contactPointID,
            workspaceID: predecessor.workspaceID,
            party: party,
            kind: predecessor.kind,
            label: label,
            displayValue: displayValue,
            preferred: preferred,
            provenance: predecessor.provenance,
            importSourceSetSHA256: predecessor.importSourceSetSHA256,
            privacyClass: predecessor.privacyClass,
            lifecycle: lifecycle,
            effectiveAt: predecessor.effectiveAt,
            retiredAt: retiredAt,
            revision: try increment(predecessor.revision),
            supersedes: try predecessor.revisionReference,
            mutationID: mutationID
        )
    }

    private func increment(_ value: UInt64) throws -> UInt64 {
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { throw PartyContactSiteRoleWorkflowFailureV1.staleRevision }
        return next
    }
}
