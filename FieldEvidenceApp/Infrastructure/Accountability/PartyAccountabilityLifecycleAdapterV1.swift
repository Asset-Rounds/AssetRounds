import Foundation
import SwiftData

private enum PartyAccountabilityLifecycleClosedCodingV1 {
    static func require<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        keys: Key.Type,
        required: Set<String>
    ) throws where Key.AllCases: Collection {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let actual = Set(raw.allKeys.map(\.stringValue))
        let allowed = Set(Key.allCases.map(\.stringValue))
        guard actual.isSubset(of: allowed) else {
            throw PartyAccountabilityFailureV1.unknownKey
        }
        guard required.isSubset(of: actual) else {
            throw PartyAccountabilityFailureV1.missingKey
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

enum PartyAccountabilityMigrationDispositionV1: String, Codable, CaseIterable, Sendable {
    case unknown = "UNKNOWN"
    case serviceProviderCandidate = "SERVICE_PROVIDER_CANDIDATE"
}

/// A zero-write migration preview.  A legacy Site label is never persisted as
/// a customer or person; only explicit shop/profile text may be presented as a
/// possible SERVICE_PROVIDER candidate for user review.
struct PartyAccountabilityMigrationPreviewV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let siteID: UUID
    let sourceText: String?
    let disposition: PartyAccountabilityMigrationDispositionV1
    let proposedRole: SitePartyRoleV1?
    let writesCanonicalData: Bool

    init(
        workspaceID: WorkspaceID,
        siteID: UUID,
        sourceText: String?
    ) throws {
        try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        try PartyAccountabilityValidationV1.requireID(siteID)
        if let sourceText {
            try PartyAccountabilityValidationV1.requireText(
                sourceText,
                maximumBytes: PartyAccountabilityLimitsV1.maximumDisplayNameBytes
            )
        }
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.siteID = siteID
        self.sourceText = sourceText
        disposition = sourceText == nil || sourceText?.isEmpty == true
            ? .unknown
            : .serviceProviderCandidate
        proposedRole = sourceText == nil || sourceText?.isEmpty == true
            ? nil
            : .serviceProvider
        writesCanonicalData = false
    }

    func validate() throws {
        let rebuilt = try Self(
            workspaceID: workspaceID,
            siteID: siteID,
            sourceText: sourceText
        )
        guard schemaVersion == Self.schemaVersion,
              disposition == rebuilt.disposition,
              proposedRole == rebuilt.proposedRole,
              !writesCanonicalData else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, siteID, sourceText, disposition,
             proposedRole, writesCanonicalData
    }

    init(from decoder: Decoder) throws {
        try PartyAccountabilityLifecycleClosedCodingV1.require(
            decoder,
            keys: CodingKeys.self,
            required: [
                "schemaVersion", "workspaceID", "siteID", "disposition",
                "writesCanonicalData",
            ]
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = try Self(
            workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
            siteID: values.decode(UUID.self, forKey: .siteID),
            sourceText: values.decodeIfPresent(String.self, forKey: .sourceText)
        )
        guard try values.decode(Int.self, forKey: .schemaVersion)
                == Self.schemaVersion,
              try values.decode(
                  PartyAccountabilityMigrationDispositionV1.self,
                  forKey: .disposition
              ) == rebuilt.disposition,
              try values.decodeIfPresent(
                  SitePartyRoleV1.self,
                  forKey: .proposedRole
              ) == rebuilt.proposedRole,
              try values.decode(Bool.self, forKey: .writesCanonicalData)
                == false else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        self = rebuilt
    }
}

/// Read/validation/projection seam for C38.  It does not save or mutate a
/// ModelContext: canonical writes continue through WorkspaceWriterV1 and its
/// WorkspaceWriterAdapterV1, which supplies the single transaction and
/// durable MutationReceiptV1.
@MainActor
final class PartyAccountabilityLifecycleAdapterV1: PartyAccountabilityLifecyclePortV1 {
    let workspaceID: WorkspaceID

    private let modelContext: ModelContext

    init(modelContext: ModelContext, workspaceID: WorkspaceID) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
    }

    func validate(_ mutation: PartyAccountabilityMutationV1) throws {
        try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        try mutation.validate()
        guard mutation.workspaceID == workspaceID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
        switch mutation {
        case let .recordParty(value):
            try validatePartyMutation(value)
        case let .appendSiteRole(value):
            try validateSiteRoleMutation(value)
        case let .appendActorSnapshot(value):
            try validateActorMutation(value)
        case let .appendQualificationSnapshot(value):
            try validateQualificationMutation(value)
        case let .appendSignoff(value):
            try validateSignoffMutation(value)
        }
    }

    /// Returns only the exact persisted values.  Current party state is not
    /// joined into actor/sign-off snapshots, so rename, retirement, and later
    /// qualification expiry cannot rewrite historic display.
    func projection(at date: Date) throws -> PartyAccountabilityProjectionV1 {
        try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        let parties = try partyRows().map { try $0.value() }
        let roles = try roleRows().map { try $0.value() }
        let actors = try actorRows().map { try $0.value() }
        let qualifications = try qualificationRows().map { try $0.value() }
        let signoffs = try signoffRows().map { try $0.value() }
        return try PartyAccountabilityProjectionV1(
            workspaceID: workspaceID,
            asOf: date,
            parties: parties,
            siteRoleEvents: roles,
            actorSnapshots: actors,
            qualificationSnapshots: qualifications,
            signoffs: signoffs
        )
    }

    func party(partyID: UUID) throws -> ServicePartyReferenceV1? {
        try PartyAccountabilityValidationV1.requireID(partyID)
        let matches = try partyRows().filter { $0.partyID == partyID }
        guard matches.count <= 1 else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        return try matches.first?.value()
    }

    func siteRoleHistory(
        siteID: UUID,
        partyID: UUID? = nil
    ) throws -> [SitePartyRoleEventV1] {
        try PartyAccountabilityValidationV1.requireID(siteID)
        if let partyID { try PartyAccountabilityValidationV1.requireID(partyID) }
        let values = try roleRows()
            .filter { row in
                row.siteID == siteID && (partyID == nil || row.partyID == partyID)
            }
            .map { try $0.value() }
        return values.sorted { Self.uuidKey($0.eventID) < Self.uuidKey($1.eventID) }
    }

    func actorSnapshots() throws -> [ActorSnapshotV1] {
        try actorRows().map { try $0.value() }
            .sorted { Self.uuidKey($0.snapshotID) < Self.uuidKey($1.snapshotID) }
    }

    func qualificationSnapshots() throws -> [QualificationSnapshotV1] {
        try qualificationRows().map { try $0.value() }
            .sorted { Self.uuidKey($0.snapshotID) < Self.uuidKey($1.snapshotID) }
    }

    func signoffSnapshots(subjectID: UUID? = nil) throws -> [SignoffSnapshotV1] {
        if let subjectID { try PartyAccountabilityValidationV1.requireID(subjectID) }
        let values = try signoffRows()
            .filter { row in subjectID == nil || row.subjectID == subjectID }
            .map { try $0.value() }
        return values.sorted { Self.uuidKey($0.snapshotID) < Self.uuidKey($1.snapshotID) }
    }

    func activeSiteRoles(
        siteID: UUID,
        at date: Date
    ) throws -> [SitePartyRoleEventV1] {
        try PartyAccountabilityValidationV1.requireID(siteID)
        guard Self.isFinite(date) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        return try projection(at: date).activeRoles(for: siteID)
    }

    func qualificationState(
        snapshotID: UUID,
        at date: Date
    ) throws -> QualificationProjectionStateV1? {
        try PartyAccountabilityValidationV1.requireID(snapshotID)
        guard Self.isFinite(date) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        guard let qualification = try qualificationSnapshots()
            .first(where: { $0.snapshotID == snapshotID }) else {
            return nil
        }
        return try projection(at: date).qualificationState(
            qualification,
            at: date
        )
    }

    /// Builds a first party record without writing it.  A separate explicit
    /// `recordParty` mutation is still required for canonical persistence.
    func makeParty(
        partyID: UUID,
        kind: ServicePartyKindV1,
        displayName: String,
        profileDescriptor: String? = nil,
        provenance: ServicePartyProvenanceV1,
        effectiveAt: Date,
        mutationID: MutationIDV1
    ) throws -> ServicePartyReferenceV1 {
        guard try party(partyID: partyID) == nil else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        guard Self.isFinite(effectiveAt) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        return try ServicePartyReferenceV1(
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
    }

    func makeRenamedParty(
        partyID: UUID,
        displayName: String,
        mutationID: MutationIDV1
    ) throws -> ServicePartyReferenceV1 {
        guard let prior = try party(partyID: partyID), prior.state == .effective else {
            throw PartyAccountabilityFailureV1.immutableHistory
        }
        guard prior.revision < UInt64.max,
              Self.isFinite(prior.effectiveAt) else {
            throw PartyAccountabilityFailureV1.limitExceeded
        }
        return try ServicePartyReferenceV1(
            partyID: prior.partyID,
            workspaceID: workspaceID,
            kind: prior.kind,
            displayName: displayName,
            profileDescriptor: prior.profileDescriptor,
            provenance: prior.provenance,
            privacyClass: prior.privacyClass,
            state: .effective,
            effectiveAt: prior.effectiveAt,
            revision: prior.revision + 1,
            mutationID: mutationID
        )
    }

    func makeRetiredParty(
        partyID: UUID,
        retiredAt: Date,
        mutationID: MutationIDV1
    ) throws -> ServicePartyReferenceV1 {
        guard let prior = try party(partyID: partyID), prior.state == .effective,
              retiredAt >= prior.effectiveAt else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        guard prior.revision < UInt64.max,
              Self.isFinite(prior.effectiveAt),
              Self.isFinite(retiredAt) else {
            throw PartyAccountabilityFailureV1.limitExceeded
        }
        return try ServicePartyReferenceV1(
            partyID: prior.partyID,
            workspaceID: workspaceID,
            kind: prior.kind,
            displayName: prior.displayName,
            profileDescriptor: prior.profileDescriptor,
            provenance: prior.provenance,
            privacyClass: prior.privacyClass,
            state: .retired,
            effectiveAt: prior.effectiveAt,
            retiredAt: retiredAt,
            revision: prior.revision + 1,
            mutationID: mutationID
        )
    }

    func makeSitePartyRoleEvent(
        eventID: UUID,
        siteID: UUID,
        partyID: UUID,
        role: SitePartyRoleV1,
        effectiveFrom: Date,
        effectiveUntil: Date? = nil,
        source: SitePartyRoleSourceV1,
        supersedesEventID: UUID? = nil,
        recordedAt: Date,
        mutationID: MutationIDV1
    ) throws -> SitePartyRoleEventV1 {
        let predecessor: SitePartyRoleEventV1?
        if let supersedesEventID {
            guard let value = try roleEvent(eventID: supersedesEventID) else {
                throw PartyAccountabilityFailureV1.immutableHistory
            }
            predecessor = value
        } else {
            predecessor = nil
        }
        let revision: UInt64
        if let predecessor {
            guard predecessor.revision < UInt64.max else {
                throw PartyAccountabilityFailureV1.limitExceeded
            }
            revision = predecessor.revision + 1
        } else {
            revision = 1
        }
        guard Self.isFinite(effectiveFrom),
              effectiveUntil.map({ Self.isFinite($0) }) ?? true,
              Self.isFinite(recordedAt) else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        let value = try SitePartyRoleEventV1(
            eventID: eventID,
            workspaceID: workspaceID,
            siteID: siteID,
            partyID: partyID,
            role: role,
            effectiveFrom: effectiveFrom,
            effectiveUntil: effectiveUntil,
            source: source,
            supersedesEventID: supersedesEventID,
            revision: revision,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        try validate(.appendSiteRole(value))
        return value
    }

    func makeActorSnapshot(
        snapshotID: UUID,
        actor: LocalActorReferenceV1,
        responsibility: ResponsibilityKindV1,
        displayNameAtTime: String? = nil,
        capturedAt: Date
    ) throws -> ActorSnapshotV1 {
        if let partyID = actor.partyID {
            guard let party = try party(partyID: partyID) else {
                throw PartyAccountabilityFailureV1.crossWorkspaceReference
            }
            try actor.validatePartyReference(party)
        } else {
            try actor.validate()
        }
        guard Self.isFinite(capturedAt) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        let value = try ActorSnapshotV1(
            snapshotID: snapshotID,
            workspaceID: workspaceID,
            actor: actor,
            responsibility: responsibility,
            displayNameAtTime: displayNameAtTime ?? actor.displayName,
            capturedAt: capturedAt
        )
        try validate(.appendActorSnapshot(value))
        return value
    }

    func makeQualificationSnapshot(
        snapshotID: UUID,
        declaredScope: String,
        issuerDisplay: String? = nil,
        credentialLocator: String? = nil,
        effectiveAt: Date? = nil,
        expiresAt: Date? = nil,
        provenance: QualificationProvenanceV1,
        capturedAt: Date
    ) throws -> QualificationSnapshotV1 {
        guard effectiveAt.map({ Self.isFinite($0) }) ?? true,
              expiresAt.map({ Self.isFinite($0) }) ?? true,
              Self.isFinite(capturedAt) else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        let value = try QualificationSnapshotV1(
            snapshotID: snapshotID,
            workspaceID: workspaceID,
            declaredScope: declaredScope,
            issuerDisplay: issuerDisplay,
            credentialLocator: credentialLocator,
            effectiveAt: effectiveAt,
            expiresAt: expiresAt,
            provenance: provenance,
            capturedAt: capturedAt
        )
        try validate(.appendQualificationSnapshot(value))
        return value
    }

    /// Constructs only a disclosed local assertion.  It never creates a
    /// cryptographic signature, identity proof, legal signature, or verified
    /// qualification claim.
    func makeLocalAssertionSignoff(
        snapshotID: UUID,
        purpose: String,
        subjectID: UUID,
        subjectRevision: UInt64,
        actor: ActorSnapshotV1,
        claimedRole: String,
        claimedRelationship: SitePartyRoleV1? = nil,
        qualification: QualificationSnapshotV1? = nil,
        disclosureRelease: SignoffIntentDisclosureReleaseV1,
        occurredAt: Date,
        recordedAt: Date,
        mutationID: MutationIDV1,
        supersedesSnapshotID: UUID? = nil
    ) throws -> SignoffSnapshotV1 {
        guard actor.workspaceID == workspaceID,
              qualification.map({ $0.workspaceID == workspaceID }) ?? true else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
        guard Self.isFinite(occurredAt),
              Self.isFinite(recordedAt) else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        try actor.validate()
        try qualification?.validate()
        let assertion = try SignoffRoleAssertionV1(
            claimedRole: claimedRole,
            claimedRelationship: claimedRelationship,
            actor: actor,
            disclosureRelease: disclosureRelease
        )
        let value = try SignoffSnapshotV1(
            snapshotID: snapshotID,
            workspaceID: workspaceID,
            purpose: purpose,
            subjectID: subjectID,
            subjectRevision: subjectRevision,
            disposition: .recordedLocalAssertion,
            method: .typedLocalAssertion,
            roleAssertion: assertion,
            qualification: qualification,
            occurredAt: occurredAt,
            recordedAt: recordedAt,
            supersedesSnapshotID: supersedesSnapshotID,
            mutationID: mutationID
        )
        try validate(.appendSignoff(value))
        return value
    }

    /// Explicitly validates the legacy Site-label boundary without writing.
    func previewLegacyServiceProvider(
        siteID: UUID,
        sourceText: String?
    ) throws -> PartyAccountabilityMigrationPreviewV1 {
        try PartyAccountabilityValidationV1.requireID(siteID)
        guard try siteExists(siteID) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        return try PartyAccountabilityMigrationPreviewV1(
            workspaceID: workspaceID,
            siteID: siteID,
            sourceText: sourceText
        )
    }

    func validateSeparationOfDuty(
        candidate: SignoffSnapshotV1
    ) throws {
        try candidate.validate()
        guard candidate.workspaceID == workspaceID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
        guard let candidateActor = candidate.roleAssertion?.actor.actorReferenceID,
              let candidateKind = candidate.roleAssertion?.actor.responsibility else {
            return
        }
        let existing = try signoffSnapshots(subjectID: candidate.subjectID)
        for prior in existing {
            guard let actor = prior.roleAssertion?.actor,
                  actor.actorReferenceID == candidateActor,
                  let priorKind = prior.roleAssertion?.actor.responsibility else {
                continue
            }
            if Self.separationConflict(candidateKind, priorKind) {
                throw PartyAccountabilityFailureV1.unsupportedClaim
            }
        }
    }

    private func validatePartyMutation(
        _ value: ServicePartyReferenceV1
    ) throws {
        guard Self.isFinite(value.effectiveAt),
              value.retiredAt.map({ Self.isFinite($0) }) ?? true else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        guard let prior = try party(partyID: value.partyID) else {
            guard value.revision == 1,
                  value.state == .effective,
                  value.retiredAt == nil else {
                throw PartyAccountabilityFailureV1.invalidValue
            }
            return
        }
        guard Self.isFinite(prior.effectiveAt),
              prior.retiredAt.map({ Self.isFinite($0) }) ?? true else {
            throw PartyAccountabilityFailureV1.immutableHistory
        }
        guard prior.profileDescriptor == value.profileDescriptor,
              prior.provenance == value.provenance,
              prior.privacyClass == value.privacyClass else {
            throw PartyAccountabilityFailureV1.immutableHistory
        }
        try value.validateSuccessor(of: prior)
        guard prior.state == .effective else {
            throw PartyAccountabilityFailureV1.immutableHistory
        }
        switch value.state {
        case .effective:
            guard value.retiredAt == nil else {
                throw PartyAccountabilityFailureV1.invalidInterval
            }
        case .retired:
            guard let retiredAt = value.retiredAt,
                  retiredAt >= prior.effectiveAt else {
                throw PartyAccountabilityFailureV1.invalidInterval
            }
        }
    }

    private func validateSiteRoleMutation(
        _ value: SitePartyRoleEventV1
    ) throws {
        guard Self.isFinite(value.effectiveFrom),
              value.effectiveUntil.map({ Self.isFinite($0) }) ?? true,
              Self.isFinite(value.recordedAt) else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        let duplicate = try roleRows().filter { $0.eventID == value.eventID }
        guard duplicate.isEmpty else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        guard try siteExists(value.siteID),
              let party = try party(partyID: value.partyID) else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
        try value.validatePartyReference(party)
        guard Self.isFinite(party.effectiveAt),
              party.retiredAt.map({ Self.isFinite($0) }) ?? true else {
            throw PartyAccountabilityFailureV1.immutableHistory
        }
        guard value.effectiveFrom >= party.effectiveAt else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        if let retiredAt = party.retiredAt {
            guard value.effectiveFrom <= retiredAt,
                  value.effectiveUntil.map({ $0 <= retiredAt }) == true else {
                throw PartyAccountabilityFailureV1.invalidInterval
            }
        }
        if let predecessorID = value.supersedesEventID {
            guard let predecessor = try roleEvent(eventID: predecessorID) else {
                throw PartyAccountabilityFailureV1.immutableHistory
            }
            try value.validateSupersession(of: predecessor)
        } else {
            guard value.revision == 1 else {
                throw PartyAccountabilityFailureV1.invalidValue
            }
        }
    }

    private func validateActorMutation(
        _ value: ActorSnapshotV1
    ) throws {
        guard Self.isFinite(value.capturedAt) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        guard try actorRows().allSatisfy({ $0.snapshotID != value.snapshotID }) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        if let partyID = value.actor.partyID {
            guard let party = try party(partyID: partyID) else {
                throw PartyAccountabilityFailureV1.crossWorkspaceReference
            }
            try value.actor.validatePartyReference(party)
        }
    }

    private func validateQualificationMutation(
        _ value: QualificationSnapshotV1
    ) throws {
        guard Self.isFinite(value.capturedAt),
              value.effectiveAt.map({ Self.isFinite($0) }) ?? true,
              value.expiresAt.map({ Self.isFinite($0) }) ?? true else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        guard try qualificationRows().allSatisfy({ $0.snapshotID != value.snapshotID }) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
    }

    private func validateSignoffMutation(
        _ value: SignoffSnapshotV1
    ) throws {
        guard Self.isFinite(value.recordedAt),
              value.occurredAt.map({ Self.isFinite($0) }) ?? true else {
            throw PartyAccountabilityFailureV1.invalidInterval
        }
        guard try signoffRows().allSatisfy({ $0.snapshotID != value.snapshotID }) else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        if let partyID = value.roleAssertion?.actor.partyID {
            guard let party = try party(partyID: partyID) else {
                throw PartyAccountabilityFailureV1.crossWorkspaceReference
            }
            try value.roleAssertion?.actor.validatePartyReference(party)
        }
        if let embeddedActor = value.roleAssertion?.actor {
            guard let persistedActor = try actorSnapshot(
                snapshotID: embeddedActor.snapshotID
            ) else {
                throw PartyAccountabilityFailureV1.invalidValue
            }
            guard persistedActor == embeddedActor else {
                throw PartyAccountabilityFailureV1.immutableHistory
            }
        }
        if let embeddedQualification = value.qualification {
            guard let persistedQualification = try qualificationSnapshot(
                snapshotID: embeddedQualification.snapshotID
            ) else {
                throw PartyAccountabilityFailureV1.invalidValue
            }
            guard persistedQualification == embeddedQualification else {
                throw PartyAccountabilityFailureV1.immutableHistory
            }
        }
        if let predecessorID = value.supersedesSnapshotID {
            guard let predecessor = try signoffSnapshot(snapshotID: predecessorID) else {
                throw PartyAccountabilityFailureV1.immutableHistory
            }
            try value.validateSupersession(of: predecessor)
        }
        try validateSeparationOfDuty(candidate: value)
        if let text = value.roleAssertion?.claimedRole.lowercased(),
           Self.containsUnsupportedClaim(text) {
            throw PartyAccountabilityFailureV1.unsupportedClaim
        }
    }

    private func roleEvent(eventID: UUID) throws -> SitePartyRoleEventV1? {
        try PartyAccountabilityValidationV1.requireID(eventID)
        let rows = try roleRows().filter { $0.eventID == eventID }
        guard rows.count <= 1 else { throw PartyAccountabilityFailureV1.invalidValue }
        return try rows.first?.value()
    }

    private func signoffSnapshot(snapshotID: UUID) throws -> SignoffSnapshotV1? {
        try PartyAccountabilityValidationV1.requireID(snapshotID)
        let rows = try signoffRows().filter { $0.snapshotID == snapshotID }
        guard rows.count <= 1 else { throw PartyAccountabilityFailureV1.invalidValue }
        return try rows.first?.value()
    }

    private func actorSnapshot(snapshotID: UUID) throws -> ActorSnapshotV1? {
        try PartyAccountabilityValidationV1.requireID(snapshotID)
        let rows = try modelContext.fetch(FetchDescriptor<ActorSnapshotRow>())
            .filter { $0.snapshotID == snapshotID }
        guard rows.count <= 1 else { throw PartyAccountabilityFailureV1.invalidValue }
        guard let row = rows.first else { return nil }
        let value = try row.value()
        guard value.workspaceID == workspaceID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
        return value
    }

    private func qualificationSnapshot(snapshotID: UUID) throws -> QualificationSnapshotV1? {
        try PartyAccountabilityValidationV1.requireID(snapshotID)
        let rows = try modelContext.fetch(FetchDescriptor<QualificationSnapshotRow>())
            .filter { $0.snapshotID == snapshotID }
        guard rows.count <= 1 else { throw PartyAccountabilityFailureV1.invalidValue }
        guard let row = rows.first else { return nil }
        let value = try row.value()
        guard value.workspaceID == workspaceID else {
            throw PartyAccountabilityFailureV1.crossWorkspaceReference
        }
        return value
    }

    private func siteExists(_ siteID: UUID) throws -> Bool {
        try PartyAccountabilityValidationV1.requireID(siteID)
        let rows = try modelContext.fetch(FetchDescriptor<Site>())
        return rows.filter { $0.id == siteID }.count == 1
    }

    private func partyRows() throws -> [ServicePartyRow] {
        try modelContext.fetch(FetchDescriptor<ServicePartyRow>())
            .filter { $0.workspaceID == workspaceID.rawValue }
    }

    private func roleRows() throws -> [SitePartyRoleEventRow] {
        try modelContext.fetch(FetchDescriptor<SitePartyRoleEventRow>())
            .filter { $0.workspaceID == workspaceID.rawValue }
    }

    private func actorRows() throws -> [ActorSnapshotRow] {
        try modelContext.fetch(FetchDescriptor<ActorSnapshotRow>())
            .filter { $0.workspaceID == workspaceID.rawValue }
    }

    private func qualificationRows() throws -> [QualificationSnapshotRow] {
        try modelContext.fetch(FetchDescriptor<QualificationSnapshotRow>())
            .filter { $0.workspaceID == workspaceID.rawValue }
    }

    private func signoffRows() throws -> [SignoffSnapshotRow] {
        try modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>())
            .filter { $0.workspaceID == workspaceID.rawValue }
    }

    private static func uuidKey(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }

    private static func containsUnsupportedClaim(_ value: String) -> Bool {
        [
            "verified",
            "certified",
            "authorized",
            "legally binding",
            "nonrepudiation",
            "cryptographic signature",
        ].contains { value.contains($0) }
    }

    private static func separationConflict(
        _ lhs: ResponsibilityKindV1,
        _ rhs: ResponsibilityKindV1
    ) -> Bool {
        let pair: Set<ResponsibilityKindV1> = [lhs, rhs]
        return pair == [.performedBy, .verifiedBy]
            || pair == [.performedBy, .approvedBy]
            || pair == [.reviewedBy, .approvedBy]
            || pair == [.verifiedBy, .approvedBy]
    }
}
