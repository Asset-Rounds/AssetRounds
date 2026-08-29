import Foundation
import SwiftData

enum OperationalContactPersistenceFailureV1: Error, Equatable, Sendable {
    case corruptRow
}

/// Canonical C46 contact state. Platform outcomes and import source bytes never
/// become durable rows; the separately enrolled intent row is the reviewed,
/// pre-handoff audit fact only.
@Model final class ServiceContactPointRow {
    @Attribute(.unique) var stableIdentity: String
    var contactPointID: UUID
    var workspaceID: UUID
    var partyID: UUID
    var kindRawValue: String
    var preferred: Bool
    var lifecycleRawValue: String
    var revision: UInt64
    var mutationID: UUID
    var contactPointSHA256: String
    var canonicalData: Data

    init(_ value: ServiceContactPointV1) throws {
        try value.validate()
        stableIdentity = Self.identity(
            workspaceID: value.workspaceID.rawValue,
            contactPointID: value.contactPointID
        )
        contactPointID = value.contactPointID
        workspaceID = value.workspaceID.rawValue
        partyID = value.party.partyID
        kindRawValue = value.kind.rawValue
        preferred = value.preferred
        lifecycleRawValue = value.lifecycle.rawValue
        revision = value.revision
        mutationID = value.mutationID.rawValue
        contactPointSHA256 = value.contactPointSHA256
        canonicalData = try OperationalContactCanonicalCodecV1.data(value)
        guard try OperationalContactCanonicalCodecV1.decode(
            ServiceContactPointV1.self, from: canonicalData
        ) == value else {
            throw OperationalContactPersistenceFailureV1.corruptRow
        }
    }

    func value() throws -> ServiceContactPointV1 {
        let value = try OperationalContactCanonicalCodecV1.decode(
            ServiceContactPointV1.self, from: canonicalData
        )
        try value.validate()
        guard stableIdentity == Self.identity(
                workspaceID: value.workspaceID.rawValue,
                contactPointID: value.contactPointID
              ),
              contactPointID == value.contactPointID,
              workspaceID == value.workspaceID.rawValue,
              partyID == value.party.partyID,
              kindRawValue == value.kind.rawValue,
              preferred == value.preferred,
              lifecycleRawValue == value.lifecycle.rawValue,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              contactPointSHA256 == value.contactPointSHA256,
              try OperationalContactCanonicalCodecV1.data(value) == canonicalData else {
            throw OperationalContactPersistenceFailureV1.corruptRow
        }
        return value
    }

    func replace(with value: ServiceContactPointV1, expectedRevision: UInt64) throws {
        let current = try self.value()
        guard current.workspaceID == value.workspaceID,
              current.contactPointID == value.contactPointID,
              current.revision == expectedRevision,
              expectedRevision < UInt64.max,
              value.revision == expectedRevision + 1,
              value.supersedes == (try current.revisionReference) else {
            throw OperationalContactFailureV1.staleRevision
        }
        let replacement = try ServiceContactPointRow(value)
        partyID = replacement.partyID
        kindRawValue = replacement.kindRawValue
        preferred = replacement.preferred
        lifecycleRawValue = replacement.lifecycleRawValue
        revision = replacement.revision
        mutationID = replacement.mutationID
        contactPointSHA256 = replacement.contactPointSHA256
        canonicalData = replacement.canonicalData
    }

    private static func identity(workspaceID: UUID, contactPointID: UUID) -> String {
        "\(workspaceID.uuidString.lowercased())|\(contactPointID.uuidString.lowercased())"
    }
}

@Model final class SystemHandoffIntentRow {
    @Attribute(.unique) var stableIdentity: String
    var intentID: UUID
    var workspaceID: UUID
    var kindRawValue: String
    var targetKindRawValue: String
    var targetID: UUID
    var targetRevision: UInt64
    var revision: UInt64
    var mutationID: UUID
    var intentSHA256: String
    var dispositionRawValue: String
    var canonicalData: Data

    init(_ value: SystemHandoffIntentV1) throws {
        try value.validate()
        stableIdentity = Self.identity(
            workspaceID: value.workspaceID.rawValue,
            intentID: value.intentID
        )
        intentID = value.intentID
        workspaceID = value.workspaceID.rawValue
        kindRawValue = value.kind.rawValue
        targetKindRawValue = value.target.kind.rawValue
        targetID = value.target.targetID
        targetRevision = value.target.expectedRevision
        revision = value.revision
        mutationID = value.mutationID.rawValue
        intentSHA256 = value.intentSHA256
        dispositionRawValue = value.disposition.rawValue
        canonicalData = try OperationalContactCanonicalCodecV1.data(value)
        guard try OperationalContactCanonicalCodecV1.decode(
            SystemHandoffIntentV1.self, from: canonicalData
        ) == value else {
            throw OperationalContactPersistenceFailureV1.corruptRow
        }
    }

    func value() throws -> SystemHandoffIntentV1 {
        let value = try OperationalContactCanonicalCodecV1.decode(
            SystemHandoffIntentV1.self, from: canonicalData
        )
        try value.validate()
        guard stableIdentity == Self.identity(
                workspaceID: value.workspaceID.rawValue,
                intentID: value.intentID
              ),
              intentID == value.intentID,
              workspaceID == value.workspaceID.rawValue,
              kindRawValue == value.kind.rawValue,
              targetKindRawValue == value.target.kind.rawValue,
              targetID == value.target.targetID,
              targetRevision == value.target.expectedRevision,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              intentSHA256 == value.intentSHA256,
              dispositionRawValue == value.disposition.rawValue,
              try OperationalContactCanonicalCodecV1.data(value) == canonicalData else {
            throw OperationalContactPersistenceFailureV1.corruptRow
        }
        return value
    }

    private static func identity(workspaceID: UUID, intentID: UUID) -> String {
        "\(workspaceID.uuidString.lowercased())|\(intentID.uuidString.lowercased())"
    }
}

/// The production handoff query reads only canonical rows. Raw destinations
/// are materialized in the protocol extension for the duration of one tap and
/// are never cached here.
@MainActor
final class OperationalContactRowQueryV1:
    OperationalContactHandoffQueryingV1,
    OperationalContactImportQueryingV1 {
    private let modelContext: ModelContext
    private let workspaceID: WorkspaceID

    init(modelContext: ModelContext, workspaceID: WorkspaceID) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
    }

    func currentServiceContactPoint(
        workspaceID: WorkspaceID,
        contactPointID: UUID
    ) async throws -> ServiceContactPointV1? {
        guard workspaceID == self.workspaceID else { return nil }
        let raw = workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<ServiceContactPointRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.contactPointID == contactPointID }
        ))
        guard rows.count <= 1 else { throw OperationalContactPersistenceFailureV1.corruptRow }
        return try rows.first?.value()
    }

    func handoffIntent(
        workspaceID: WorkspaceID,
        intentID: UUID
    ) async throws -> SystemHandoffIntentV1? {
        guard workspaceID == self.workspaceID else { return nil }
        let raw = workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.intentID == intentID }
        ))
        guard rows.count <= 1 else { throw OperationalContactPersistenceFailureV1.corruptRow }
        return try rows.first?.value()
    }

    func currentImportState(
        workspaceID: WorkspaceID,
        partyIDs: [UUID]
    ) async throws -> OperationalContactImportCurrentStateV1 {
        guard workspaceID == self.workspaceID else {
            throw OperationalContactFailureV1.crossWorkspaceReference
        }
        let requested = partyIDs.sorted { $0.uuidString < $1.uuidString }
        guard !requested.isEmpty,
              requested.count == Set(requested).count,
              requested.count <= OperationalContactLimitsV1.maximumMutationContacts else {
            throw OperationalContactFailureV1.invalidValue
        }
        let requestedSet = Set(requested)
        let raw = workspaceID.rawValue

        // Both fetches run synchronously on this query's MainActor-isolated
        // ModelContext. No suspension or caller-provided subset can occur
        // between the Party authority read and the complete current contact
        // scope read used to construct one import mutation.
        let parties = try modelContext.fetch(FetchDescriptor<ServicePartyRow>(
            predicate: #Predicate { $0.workspaceID == raw }
        )).map { try $0.value() }.filter { requestedSet.contains($0.partyID) }
        let contacts = try modelContext.fetch(FetchDescriptor<ServiceContactPointRow>(
            predicate: #Predicate { $0.workspaceID == raw }
        )).map { try $0.value() }.filter { requestedSet.contains($0.party.partyID) }

        guard Set(parties.map(\.partyID)).count == parties.count else {
            throw OperationalContactPersistenceFailureV1.corruptRow
        }
        let partyByID = Dictionary(uniqueKeysWithValues: parties.map {
            ($0.partyID, $0)
        })
        guard Set(partyByID.keys) == requestedSet,
              Set(contacts.map(\.contactPointID)).count == contacts.count,
              contacts.allSatisfy({
                $0.workspaceID == workspaceID
                    && partyByID[$0.party.partyID] == $0.party
              }) else {
            throw OperationalContactPersistenceFailureV1.corruptRow
        }

        var expectedRevisions: [String: Int64] = [:]
        var expectedContactDigests: [String: String] = [:]
        for party in parties {
            let identity = try WorkspaceEntityIdentityV1(
                kind: .serviceParty,
                id: party.partyID
            )
            guard party.revision <= UInt64(Int64.max),
                  expectedRevisions.updateValue(
                    Int64(party.revision), forKey: identity.stableKey
                  ) == nil else {
                throw OperationalContactPersistenceFailureV1.corruptRow
            }
        }
        for contact in contacts {
            let identity = try WorkspaceEntityIdentityV1(
                kind: .serviceContactPoint,
                id: contact.contactPointID
            )
            guard contact.revision <= UInt64(Int64.max),
                  expectedRevisions.updateValue(
                    Int64(contact.revision), forKey: identity.stableKey
                  ) == nil else {
                throw OperationalContactPersistenceFailureV1.corruptRow
            }
            expectedContactDigests[identity.stableKey] = contact.contactPointSHA256
        }
        let revisionRows = try modelContext.fetch(
            FetchDescriptor<EntityMutationRevisionRow>()
        ).filter { expectedRevisions[$0.stableIdentity] != nil }
        guard revisionRows.count == expectedRevisions.count,
              Set(revisionRows.map(\.stableIdentity))
                == Set(expectedRevisions.keys),
              revisionRows.allSatisfy({ row in
                row.revision == expectedRevisions[row.stableIdentity]
                    && row.revision > 0
                    && row.externalProjectionSHA256 != nil
                    && (expectedContactDigests[row.stableIdentity].map {
                        $0 == row.externalProjectionSHA256
                    } ?? true)
              }) else {
            throw OperationalContactPersistenceFailureV1.corruptRow
        }
        return try OperationalContactImportCurrentStateV1(
            parties: parties,
            contacts: contacts
        )
    }

    func currentSiteDirectionsSnapshot(
        workspaceID: WorkspaceID,
        siteID: UUID
    ) async throws -> SiteDirectionsTargetSnapshotV1? {
        guard workspaceID == self.workspaceID else { return nil }
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        guard sites.count <= 1 else { throw OperationalContactPersistenceFailureV1.corruptRow }
        guard let site = sites.first else { return nil }
        let identity = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
        let key = identity.stableKey
        let revisions = try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>(
            predicate: #Predicate { $0.stableIdentity == key }
        ))
        guard revisions.count == 1, let revisionRow = revisions.first,
              revisionRow.revision > 0 else {
            throw OperationalContactPersistenceFailureV1.corruptRow
        }
        let revision = UInt64(revisionRow.revision)
        let value = V4BackupSiteDTO(
            id: site.id,
            schemaVersion: site.schemaVersion,
            label: site.label,
            address: site.address,
            timeZoneID: site.timeZoneID,
            createdAt: site.createdAt,
            updatedAt: site.updatedAt
        )
        let digest = try WorkspaceMutationCanonicalV1.sha256(
            OperationalContactSiteDigestBasisV1(
                identity: identity,
                revision: revision,
                value: value
            )
        )
        return try SiteDirectionsTargetSnapshotV1(
            currentTarget: SystemHandoffTargetReferenceV1(
                workspaceID: workspaceID,
                kind: .site,
                targetID: siteID,
                expectedRevision: revision,
                expectedSHA256: digest
            ),
            exactAddress: site.address
        )
    }
}

private struct OperationalContactSiteDigestBasisV1: Codable {
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
    let value: V4BackupSiteDTO
}

enum C46OperationalContactBoundary_55{static let persistentFamilies=OperationalContactPersistenceEnrollmentV1.persistentFamilies;static let platformOutcomesPersistent=false}
