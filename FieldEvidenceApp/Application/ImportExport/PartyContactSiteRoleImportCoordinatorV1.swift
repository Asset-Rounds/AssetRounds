import Foundation

enum PartyContactSiteRoleImportSourceKindV1: String, Codable, CaseIterable, Sendable {
    case parties = "PARTIES_V1"
    case partyContacts = "PARTY_CONTACTS_V1"
    case sitePartyRoles = "SITE_PARTY_ROLES_V1"

    var orderIndex: Int {
        switch self {
        case .parties: 0
        case .partyContacts: 1
        case .sitePartyRoles: 2
        }
    }
}

struct PartyContactSiteRoleImportSourceDescriptorV1: Codable, Equatable, Sendable {
    let kind: PartyContactSiteRoleImportSourceKindV1
    let fileName: String
    let byteCount: Int64
    let sha256: String
    let leaseID: UUID

    init(
        kind: PartyContactSiteRoleImportSourceKindV1,
        fileName: String,
        byteCount: Int64,
        sha256: String,
        leaseID: UUID
    ) throws {
        try ImportBulkCanonicalCodecV1.requireText(fileName)
        try ImportBulkCanonicalCodecV1.requireDigest(sha256)
        try ImportBulkCanonicalCodecV1.requireID(leaseID)
        guard byteCount > 0, byteCount <= ImportBulkLimitsV1.maximumSourceBytes else {
            throw ImportBulkFailureV1.limitExceeded
        }
        self.kind = kind
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
        self.leaseID = leaseID
    }
}

/// A source-byte-free, immutable binding for the three topologically ordered
/// scratch files. Contact values and raw CSV bytes never enter this manifest.
struct PartyContactSiteRoleImportSourceManifestV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let files: [PartyContactSiteRoleImportSourceDescriptorV1]
    let totalByteCount: Int64
    let manifestSHA256: String

    init(
        workspaceID: WorkspaceID,
        files: [PartyContactSiteRoleImportSourceDescriptorV1]
    ) throws {
        let ordered = files.sorted { $0.kind.orderIndex < $1.kind.orderIndex }
        guard ordered.map(\.kind) == [.parties, .partyContacts, .sitePartyRoles],
              Set(ordered.map(\.kind)).count == ordered.count,
              Set(ordered.map(\.fileName)).count == ordered.count,
              Set(ordered.map(\.leaseID)).count == ordered.count else {
            throw ImportBulkFailureV1.unsupportedSchema
        }
        var total: Int64 = 0
        for file in ordered {
            let result = total.addingReportingOverflow(file.byteCount)
            guard !result.overflow, result.partialValue <= ImportBulkLimitsV1.maximumSourceBytes else {
                throw ImportBulkFailureV1.limitExceeded
            }
            total = result.partialValue
        }
        self.workspaceID = workspaceID
        self.files = ordered
        totalByteCount = total
        manifestSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(workspaceID: workspaceID, files: ordered, totalByteCount: total)
        )
    }

    var leaseIDs: [UUID] { files.map(\.leaseID) }

    func contactImportSourceSet() throws -> ImportSourceSetV1 {
        try ImportSourceSetV1(
            workspaceID: workspaceID,
            files: files.map {
                try ImportSourceFileV1(
                    schemaID: $0.kind.rawValue,
                    schemaVersion: 1,
                    fileName: $0.fileName,
                    orderIndex: $0.kind.orderIndex,
                    byteCount: $0.byteCount,
                    sha256: $0.sha256
                )
            }
        )
    }

    private struct DigestBasis: Codable {
        let workspaceID: WorkspaceID
        let files: [PartyContactSiteRoleImportSourceDescriptorV1]
        let totalByteCount: Int64
    }
}

enum PartyContactSiteRoleImportGroupV1: String, Codable, CaseIterable, Sendable {
    case parties = "PARTIES"
    case contacts = "PARTY_CONTACTS"
    case siteRoles = "SITE_PARTY_ROLES"
}

struct PartyContactSiteRoleImportDispositionV1: Codable, Equatable, Sendable {
    let group: PartyContactSiteRoleImportGroupV1
    let rowIndex: Int
    let stableID: UUID
    let expectedRevision: UInt64
    let disposition: ImportRowDispositionV1
    let reason: ImportReasonCodeV1
    let rowSHA256: String

    init(
        group: PartyContactSiteRoleImportGroupV1,
        rowIndex: Int,
        stableID: UUID,
        expectedRevision: UInt64,
        rowSHA256: String
    ) throws {
        guard rowIndex > 0 else { throw ImportBulkFailureV1.invalidValue }
        try ImportBulkCanonicalCodecV1.requireID(stableID)
        try ImportBulkCanonicalCodecV1.requireDigest(rowSHA256)
        self.group = group
        self.rowIndex = rowIndex
        self.stableID = stableID
        self.expectedRevision = expectedRevision
        disposition = expectedRevision == 0 ? .create : .updateExactMatch
        reason = expectedRevision == 0 ? .exactStableKeyCreate : .exactStableKeyUpdate
        self.rowSHA256 = rowSHA256
    }
}

struct PartyContactSiteRoleImportPreparedV1: Sendable {
    let sourceManifest: PartyContactSiteRoleImportSourceManifestV1
    let dispositions: [PartyContactSiteRoleImportDispositionV1]
    let mutation: PartyContactSiteRoleImportMutationV1
    let preview: ImportBulkPreviewV1
    let sourceBindingSHA256: String

    /// Binds already validated canonical post-images to the exact three CSV
    /// families. Identity joins are UUID-only; descriptive/contact fields are
    /// compared for equality but never used for lookup or reconciliation.
    init(
        sourceManifest: PartyContactSiteRoleImportSourceManifestV1,
        partyRows: [PartyCSVRowV1],
        contactRows: [PartyContactCSVRowV1],
        siteRoleRows: [SitePartyRoleCSVRowV1],
        mutation: PartyContactSiteRoleImportMutationV1,
        workspaceRevisionSHA256: String,
        importedAt: Date
    ) throws {
        try PartiesCSVContractV1.validateRows(partyRows)
        try SitePartyRolesCSVContractV1.validateRows(siteRoleRows)
        try mutation.validate()
        try ImportBulkCanonicalCodecV1.requireDigest(workspaceRevisionSHA256)
        guard sourceManifest.workspaceID == mutation.workspaceID,
              !contactRows.isEmpty,
              contactRows.map(\.rowIndex) == Array(1...contactRows.count),
              Set(contactRows.map(\.contactPointID)).count == contactRows.count else {
            throw ImportBulkFailureV1.invalidValue
        }
        let parties = try mutation.partyMutations.map { value -> ServicePartyReferenceV1 in
            guard case let .recordParty(party) = value else { throw ImportBulkFailureV1.invalidValue }
            return party
        }
        let roles = try mutation.siteRoleMutations.map { value -> SitePartyRoleEventV1 in
            guard case let .appendSiteRole(role) = value else { throw ImportBulkFailureV1.invalidValue }
            return role
        }
        let partyByID = Dictionary(uniqueKeysWithValues: parties.map { ($0.partyID, $0) })
        let roleByID = Dictionary(uniqueKeysWithValues: roles.map { ($0.eventID, $0) })
        let contactByID = Dictionary(uniqueKeysWithValues:
            mutation.operationalContactMutation.successors.map { ($0.contactPointID, $0) }
        )
        guard partyRows.count == parties.count,
              contactRows.count == contactByID.count,
              siteRoleRows.count == roles.count else {
            throw ImportBulkFailureV1.invalidValue
        }
        for row in partyRows {
            guard let value = partyByID[row.partyID],
                  value.kind == row.kind,
                  value.displayName == row.displayName,
                  value.profileDescriptor == row.profileDescriptor,
                  value.provenance == row.provenance,
                  value.state == row.state,
                  value.effectiveAt == row.effectiveAt,
                  value.retiredAt == row.retiredAt,
                  value.revision == row.revision else { throw ImportBulkFailureV1.invalidValue }
        }
        for row in contactRows {
            guard let value = contactByID[row.contactPointID],
                  value.party.partyID == row.partyID,
                  value.kind == row.kind,
                  value.label == row.label,
                  value.displayValue == row.displayValue,
                  value.preferred == row.preferred,
                  value.effectiveAt == row.effectiveAt,
                  value.retiredAt == row.retiredAt,
                  value.revision == row.revision else { throw ImportBulkFailureV1.invalidValue }
        }
        for row in siteRoleRows {
            guard let value = roleByID[row.eventID],
                  value.siteID == row.siteID,
                  value.partyID == row.partyID,
                  value.role == row.role,
                  value.effectiveFrom == row.effectiveFrom,
                  value.effectiveUntil == row.effectiveUntil,
                  value.source == row.source,
                  value.supersedesEventID == row.supersedesEventID,
                  value.revision == row.revision,
                  value.recordedAt == row.recordedAt else { throw ImportBulkFailureV1.invalidValue }
        }
        guard mutation.operationalContactMutation.importSourceSet
                == (try sourceManifest.contactImportSourceSet()) else {
            throw ImportBulkFailureV1.invalidValue
        }

        let binding = try ImportBulkCanonicalCodecV1.sha256(
            BindingBasis(
                sourceManifestSHA256: sourceManifest.manifestSHA256,
                partyRows: partyRows,
                contactRows: contactRows,
                siteRoleRows: siteRoleRows,
                workspaceRevisionSHA256: workspaceRevisionSHA256,
                expectedRevision: mutation.expectedRevision
            )
        )
        let built = try Self.makePreview(
            sourceManifest: sourceManifest,
            sourceBindingSHA256: binding,
            workspaceID: mutation.workspaceID,
            workspaceRevisionSHA256: workspaceRevisionSHA256,
            importedAt: importedAt
        )
        guard try built.bulkPlan.mutationID(chunkIndex: 0, rowIndex: 0) == mutation.mutationID else {
            throw ImportBulkFailureV1.invalidValue
        }
        self.sourceManifest = sourceManifest
        dispositions = try Self.makeDispositions(
            partyRows: partyRows,
            contactRows: contactRows,
            siteRoleRows: siteRoleRows,
            mutation: mutation
        )
        self.mutation = mutation
        preview = built
        sourceBindingSHA256 = binding
    }

    var contactSafeDiagnostics: [PartyContactSiteRoleImportDispositionV1] { dispositions }
    var defaultContactExportEnabled: Bool { PartyContactsCSVContractV1.defaultExportEnabled }

    /// Breaks the payload/plan/mutation construction cycle without weakening
    /// determinism. Callers derive this ID first, construct the canonical
    /// post-images with it, then pass that mutation to the initializer above.
    static func deterministicMutationID(
        sourceManifest: PartyContactSiteRoleImportSourceManifestV1,
        partyRows: [PartyCSVRowV1],
        contactRows: [PartyContactCSVRowV1],
        siteRoleRows: [SitePartyRoleCSVRowV1],
        expectedRevision: WorkspaceExpectedRevisionV1,
        workspaceRevisionSHA256: String,
        importedAt: Date
    ) throws -> MutationIDV1 {
        try PartiesCSVContractV1.validateRows(partyRows)
        try SitePartyRolesCSVContractV1.validateRows(siteRoleRows)
        try ImportBulkCanonicalCodecV1.requireDigest(workspaceRevisionSHA256)
        guard sourceManifest.workspaceID == expectedRevision.workspaceID,
              !contactRows.isEmpty,
              contactRows.map(\.rowIndex) == Array(1...contactRows.count),
              Set(contactRows.map(\.contactPointID)).count == contactRows.count else {
            throw ImportBulkFailureV1.invalidValue
        }
        let binding = try ImportBulkCanonicalCodecV1.sha256(
            BindingBasis(
                sourceManifestSHA256: sourceManifest.manifestSHA256,
                partyRows: partyRows,
                contactRows: contactRows,
                siteRoleRows: siteRoleRows,
                workspaceRevisionSHA256: workspaceRevisionSHA256,
                expectedRevision: expectedRevision
            )
        )
        let preview = try makePreview(
            sourceManifest: sourceManifest,
            sourceBindingSHA256: binding,
            workspaceID: expectedRevision.workspaceID,
            workspaceRevisionSHA256: workspaceRevisionSHA256,
            importedAt: importedAt
        )
        return try preview.bulkPlan.mutationID(chunkIndex: 0, rowIndex: 0)
    }

    private static func makePreview(
        sourceManifest: PartyContactSiteRoleImportSourceManifestV1,
        sourceBindingSHA256: String,
        workspaceID: WorkspaceID,
        workspaceRevisionSHA256: String,
        importedAt: Date
    ) throws -> ImportBulkPreviewV1 {
        let sourceID = try ImportBulkCanonicalCodecV1.deterministicUUID(
            namespace: "party-contact-site-role-source-v1",
            basis: sourceManifest.manifestSHA256
        )
        let leaseID = try ImportBulkCanonicalCodecV1.deterministicUUID(
            namespace: "party-contact-site-role-lease-v1",
            basis: sourceManifest.leaseIDs
        )
        let source = try ImportSourceV1(
            sourceID: sourceID,
            workspaceID: workspaceID,
            kind: .userSelectedFile,
            sourceSHA256: sourceManifest.manifestSHA256,
            byteCount: sourceManifest.totalByteCount,
            leaseID: leaseID,
            importedAt: importedAt
        )
        let columns = try [
            ImportSchemaColumnV1(key: "source_binding_sha256", scalar: .text,
                                required: true, editableOnExactUpdate: false,
                                maximumCellBytes: 64, maximumScalars: 64),
        ]
        let schema = try ImportSchemaReleaseV1(
            releaseID: "PARTY_CONTACT_SITE_ROLE_ATOMIC_V1",
            release: 1,
            entityKind: .atomicWorkspaceBundle,
            externalKeyColumn: "source_binding_sha256",
            columns: columns,
            budget: ImportStreamingBudgetV1(
                maximumSourceBytes: ImportBulkLimitsV1.maximumSourceBytes,
                maximumRows: 1,
                maximumColumns: 1,
                maximumCellBytes: 64,
                maximumScalarsPerCell: 64
            )
        )
        let identity = try ImportRowIdentityV1(
            workspaceID: workspaceID,
            sourceSHA256: source.sourceSHA256,
            sourceOrdinal: 1,
            canonicalRowSHA256: sourceBindingSHA256,
            stableExternalKey: sourceBindingSHA256,
            schemaReleaseID: schema.releaseID,
            schemaRelease: schema.release
        )
        let mappedFields = try [ImportMappedFieldV1(
            key: "source_binding_sha256",
            value: sourceBindingSHA256
        )]
        let commandID = "apply_party_contact_site_role_import"
        let command = try ImportProposedCommandV1(
            commandID: commandID,
            kind: .applyAtomicWorkspaceBundle,
            targetStableID: nil,
            expectedRevision: nil,
            dependencyCommandIDs: [],
            payloadSHA256: ImportProposedCommandV1.canonicalPayloadSHA256(
                commandID: commandID,
                kind: .applyAtomicWorkspaceBundle,
                targetStableID: nil,
                expectedRevision: nil,
                dependencyCommandIDs: [],
                rowIdentity: identity,
                schemaRelease: schema,
                mappedFields: mappedFields
            )
        )
        let row = try ImportPlanRowV1(
            identity: identity,
            disposition: .create,
            reasons: [.exactStableKeyCreate],
            mappedFields: mappedFields,
            commands: [command],
            expectedTargetRevision: nil
        )
        let planID = try ImportPlanV1.deterministicPlanID(
            workspaceID: workspaceID,
            source: source,
            schemaRelease: schema,
            mappingProfileSHA256: sourceBindingSHA256,
            workspaceRevisionSHA256: workspaceRevisionSHA256,
            rows: [row]
        )
        let plan = try ImportPlanV1(
            planID: planID,
            workspaceID: workspaceID,
            source: source,
            schemaRelease: schema,
            mappingProfileSHA256: sourceBindingSHA256,
            workspaceRevisionSHA256: workspaceRevisionSHA256,
            rows: [row]
        )
        let expectedMutationID = try BulkCommandPlanV1.deterministicMutationID(
            importPlanID: plan.planID,
            chunkIndex: 0,
            rowIdentitySHA256: identity.identitySHA256
        )
        let chunk = try BulkChunkPlanV1(
            chunkIndex: 0,
            rowIdentitySHA256s: [identity.identitySHA256],
            mutationIDs: [expectedMutationID]
        )
        let bulkPlanID = try BulkCommandPlanV1.deterministicBulkPlanID(
            importPlan: plan,
            atomicity: .allOrNothing,
            chunks: [chunk]
        )
        let bulk = try BulkCommandPlanV1(
            bulkPlanID: bulkPlanID,
            importPlan: plan,
            atomicity: .allOrNothing,
            chunks: [chunk]
        )
        return try ImportBulkPreviewV1(importPlan: plan, bulkPlan: bulk)
    }

    private static func makeDispositions(
        partyRows: [PartyCSVRowV1],
        contactRows: [PartyContactCSVRowV1],
        siteRoleRows: [SitePartyRoleCSVRowV1],
        mutation: PartyContactSiteRoleImportMutationV1
    ) throws -> [PartyContactSiteRoleImportDispositionV1] {
        let expected = mutation.expectedRevision
        func revision(_ kind: WorkspaceEntityKindV1, _ id: UUID) throws -> UInt64 {
            let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
            guard let row = expected.entityRevisions.first(where: { $0.identity == identity }) else {
                throw ImportBulkFailureV1.staleRevision
            }
            return row.revision
        }
        let parties = try partyRows.map {
            try PartyContactSiteRoleImportDispositionV1(
                group: .parties, rowIndex: $0.rowIndex, stableID: $0.partyID,
                expectedRevision: revision(.serviceParty, $0.partyID),
                rowSHA256: ImportBulkCanonicalCodecV1.sha256($0)
            )
        }
        let contacts = try contactRows.map {
            try PartyContactSiteRoleImportDispositionV1(
                group: .contacts, rowIndex: $0.rowIndex, stableID: $0.contactPointID,
                expectedRevision: revision(.serviceContactPoint, $0.contactPointID),
                rowSHA256: ImportBulkCanonicalCodecV1.sha256($0)
            )
        }
        let roles = try siteRoleRows.map {
            try PartyContactSiteRoleImportDispositionV1(
                group: .siteRoles, rowIndex: $0.rowIndex, stableID: $0.eventID,
                expectedRevision: revision(.sitePartyRoleEvent, $0.eventID),
                rowSHA256: ImportBulkCanonicalCodecV1.sha256($0)
            )
        }
        return parties + contacts + roles
    }

    private struct BindingBasis: Codable {
        let sourceManifestSHA256: String
        let partyRows: [PartyCSVRowV1]
        let contactRows: [PartyContactCSVRowV1]
        let siteRoleRows: [SitePartyRoleCSVRowV1]
        let workspaceRevisionSHA256: String
        let expectedRevision: WorkspaceExpectedRevisionV1
    }
}

struct PartyContactSiteRoleImportMaterializerV1: ImportWorkspaceCommandMaterializingV1 {
    let prepared: PartyContactSiteRoleImportPreparedV1

    func materialize(
        _ context: ImportCommandMaterializationContextV1
    ) throws -> WorkspaceMutationRequestV1 {
        let preview = prepared.preview
        guard context.plan == preview.importPlan,
              context.chunkIndex == 0,
              context.row == preview.importPlan.rows.first,
              context.command.kind == .applyAtomicWorkspaceBundle,
              context.command.targetStableID == nil,
              context.command.expectedRevision == nil,
              context.command.dependencyCommandIDs.isEmpty,
              context.mutationID == prepared.mutation.mutationID,
              try normalizedCASBasisMatches(context.expectedRevision) else {
            throw ImportBulkFailureV1.changedInputQuarantined
        }
        return try prepared.mutation.canonicalWorkspaceMutationRequest()
    }

    /// C08 supplies the full, live snapshot.  The aggregate must additionally
    /// carry zero-revision entries for the Party/contact/role post-images it
    /// creates, so raw expected-revision equality would quarantine every valid
    /// new-identity import.  Compare a fail-closed normalized basis instead.
    private func normalizedCASBasisMatches(
        _ live: WorkspaceExpectedRevisionV1
    ) throws -> Bool {
        let expected = prepared.mutation.expectedRevision
        guard live.workspaceID == expected.workspaceID,
              live.generationID == expected.generationID,
              live.writerInstanceID == expected.writerInstanceID,
              live.workspaceRevision == expected.workspaceRevision else {
            return false
        }

        func revisionMap(
            _ rows: [WorkspaceEntityRevisionV1]
        ) -> [WorkspaceEntityIdentityV1: UInt64]? {
            guard Set(rows.map(\.identity)).count == rows.count else { return nil }
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.identity, $0.revision) })
        }

        guard let liveByIdentity = revisionMap(live.entityRevisions),
              let expectedByIdentity = revisionMap(expected.entityRevisions) else {
            return false
        }

        // A full live snapshot may never lose, alter, or replace unrelated
        // rows in the prepared basis.
        guard liveByIdentity.allSatisfy({ expectedByIdentity[$0.key] == $0.value }) else {
            return false
        }

        let requiredConcurrency = Set(try prepared.mutation.concurrencyIdentities)
        // Existing aggregate dependencies (notably every bound Site) must be
        // present in the live snapshot at their exact nonzero revision.
        for identity in requiredConcurrency {
            guard let revision = expectedByIdentity[identity] else { return false }
            if revision > 0, liveByIdentity[identity] != revision { return false }
        }

        // The only allowed prepared-only rows are this aggregate's own new
        // concurrency identities, each absent live and explicitly zero.
        var normalized = liveByIdentity
        for (identity, revision) in expectedByIdentity where liveByIdentity[identity] == nil {
            guard requiredConcurrency.contains(identity), revision == 0 else {
                return false
            }
            normalized[identity] = revision
        }
        return normalized == expectedByIdentity
    }
}

enum PartyContactSiteRoleImportProductionRegistrationV1 {
    static func make(
        prepared: PartyContactSiteRoleImportPreparedV1
    ) throws -> ImportBulkMaterializerRegistrationV1 {
        try ImportBulkMaterializerRegistrationV1(
            kind: .applyAtomicWorkspaceBundle,
            materializer: PartyContactSiteRoleImportMaterializerV1(prepared: prepared),
            allowedWorkspaceCommandKinds: [.applyPartyContactSiteRoleImport]
        )
    }
}

protocol PartyContactSiteRoleImportScratchDiscardingV1: Sendable {
    func discard(leaseIDs: [UUID]) throws
}

@MainActor
final class PartyContactSiteRoleImportCoordinatorV1 {
    private let bulk: ImportBulkCoordinatorV1
    private let scratch: any PartyContactSiteRoleImportScratchDiscardingV1

    init(
        bulk: ImportBulkCoordinatorV1,
        scratch: any PartyContactSiteRoleImportScratchDiscardingV1
    ) {
        self.bulk = bulk
        self.scratch = scratch
    }

    func preview(
        _ prepared: PartyContactSiteRoleImportPreparedV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String
    ) throws -> ImportBulkPreviewV1 {
        try bulk.preview(
            importPlan: prepared.preview.importPlan,
            bulkPlan: prepared.preview.bulkPlan,
            currentSourceSHA256: currentSourceSHA256,
            currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256
        )
    }

    func begin(
        sessionID: UUID,
        prepared: PartyContactSiteRoleImportPreparedV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String
    ) throws -> BulkSessionV1 {
        try bulk.begin(
            sessionID: sessionID,
            preview: prepared.preview,
            currentSourceSHA256: currentSourceSHA256,
            currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256
        )
    }

    /// Explicit commit, deterministic retry, and effect-before-receipt replay
    /// are delegated intact to the incumbent C08 session engine.
    func commitOrResume(
        session: BulkSessionV1,
        prepared: PartyContactSiteRoleImportPreparedV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String,
        cancellationRequested: Bool
    ) throws -> BulkSessionV1 {
        try bulk.commitFirstMissingChunk(
            session: session,
            importPlan: prepared.preview.importPlan,
            bulkPlan: prepared.preview.bulkPlan,
            currentSourceSHA256: currentSourceSHA256,
            currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
            cancellationRequested: cancellationRequested
        )
    }

    func discardScratch(for prepared: PartyContactSiteRoleImportPreparedV1) throws {
        try scratch.discard(leaseIDs: prepared.sourceManifest.leaseIDs)
    }
}
