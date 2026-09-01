import Foundation

private enum PartyAccountabilityCoordinatorClosedCodingV1 {
    static func require<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        keys: Key.Type,
        required: Set<String>? = nil
    ) throws where Key.AllCases: Collection {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let actual = Set(raw.allKeys.map(\.stringValue))
        let allowed = Set(Key.allCases.map(\.stringValue))
        guard actual.isSubset(of: allowed),
              (required ?? allowed).isSubset(of: actual) else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
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

enum PartyAccountabilityCoordinatorFailureV1: Error, Equatable, Sendable {
    case invalidPlan
    case staleRevision
    case missingDurableReceipt
    case receiptMismatch
}

/// The application-facing input to one accountability mutation.  The
/// expected revision is intentionally carried through the plan instead of
/// being obtained at commit time; a preview therefore cannot silently turn
/// into an optimistic write.
struct PartyAccountabilityPreviewBasisV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutation: PartyAccountabilityMutationV1

    init(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutation: PartyAccountabilityMutationV1
    ) throws {
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.mutation = mutation
        try validate()
    }

    func validate() throws {
        try mutation.validate()
        guard expectedRevision.workspaceID == workspaceID,
              mutation.workspaceID == workspaceID else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
        guard expectedRevision.entityRevisions.map(\.identity.stableKey)
                == expectedRevision.entityRevisions.map(\.identity.stableKey).sorted() else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, expectedRevision, mutation
    }

    init(from decoder: Decoder) throws {
        try PartyAccountabilityCoordinatorClosedCodingV1.require(
            decoder,
            keys: CodingKeys.self
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workspaceID: try values.decode(WorkspaceID.self, forKey: .workspaceID),
            expectedRevision: try values.decode(
                WorkspaceExpectedRevisionV1.self,
                forKey: .expectedRevision
            ),
            mutation: try values.decode(
                PartyAccountabilityMutationV1.self,
                forKey: .mutation
            )
        )
    }
}

/// A planned C38 write.  `operationID` is a process-facing plan identity;
/// `mutationID` is the canonical writer idempotency identity.
struct PartyAccountabilityChangePlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let mutationID: MutationIDV1
    let basis: PartyAccountabilityPreviewBasisV1
    let planSHA256: String

    init(
        operationID: UUID,
        mutationID: MutationIDV1,
        basis: PartyAccountabilityPreviewBasisV1
    ) throws {
        guard operationID != Self.zeroUUID else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
        try basis.validate()
        guard basis.expectedRevision.workspaceRevision < UInt64(Int64.max) else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
        let identity = try basis.mutation.affectedIdentity
        let expected = Dictionary(
            uniqueKeysWithValues: basis.expectedRevision.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        guard let expectedEntityRevision = expected[identity],
              Self.expectedEntityRevision(
                  for: basis.mutation,
                  expected: expectedEntityRevision
              ) else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
        if let embeddedMutationID = basis.mutation.mutationID,
           embeddedMutationID != mutationID {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }

        schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.mutationID = mutationID
        self.basis = basis
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                operationID: operationID,
                mutationID: mutationID,
                basis: basis
            )
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              operationID != Self.zeroUUID else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
        try basis.validate()
        guard basis.expectedRevision.workspaceRevision < UInt64(Int64.max),
              MutationEnvelopeV1.isSHA256(planSHA256) else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
        let identity = try basis.mutation.affectedIdentity
        let expected = Dictionary(
            uniqueKeysWithValues: basis.expectedRevision.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        guard let expectedEntityRevision = expected[identity],
              Self.expectedEntityRevision(
                  for: basis.mutation,
                  expected: expectedEntityRevision
              ),
              basis.mutation.mutationID.map({ $0 == mutationID }) ?? true,
              planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                  DigestBasis(
                      schemaVersion: schemaVersion,
                      operationID: operationID,
                      mutationID: mutationID,
                      basis: basis
                  )
              )) else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
    }

    private static func expectedEntityRevision(
        for mutation: PartyAccountabilityMutationV1,
        expected: UInt64
    ) -> Bool {
        switch mutation {
        case let .recordParty(value):
            return expected < UInt64.max && value.revision == expected + 1
        case .appendSiteRole,
             .appendActorSnapshot,
             .appendQualificationSnapshot,
             .appendSignoff:
            // All four are append-only identities.  A successor relationship
            // is represented by a new event/snapshot, not an in-place row.
            return expected == 0
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let operationID: UUID
        let mutationID: MutationIDV1
        let basis: PartyAccountabilityPreviewBasisV1
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, operationID, mutationID, basis, planSHA256
    }

    init(from decoder: Decoder) throws {
        try PartyAccountabilityCoordinatorClosedCodingV1.require(
            decoder,
            keys: CodingKeys.self
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = try Self(
            operationID: try values.decode(UUID.self, forKey: .operationID),
            mutationID: try values.decode(MutationIDV1.self, forKey: .mutationID),
            basis: try values.decode(
                PartyAccountabilityPreviewBasisV1.self,
                forKey: .basis
            )
        )
        guard try values.decode(Int.self, forKey: .schemaVersion)
                == Self.schemaVersion,
              try values.decode(String.self, forKey: .planSHA256)
                == rebuilt.planSHA256 else {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
        self = rebuilt
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// Receipt returned by the canonical workspace writer, with a small C38
/// binding that proves the requested entity and expected revision were the
/// ones committed.  Historic snapshots are carried by the durable receipt;
/// this type never reconstructs them from a current Party row.
struct PartyAccountabilityChangeReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let planSHA256: String
    let mutationReceipt: MutationReceiptV1
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let affectedIdentity: WorkspaceEntityIdentityV1
    let committedAt: Date
    let receiptSHA256: String

    init(
        plan: PartyAccountabilityChangePlanV1,
        mutationReceipt: MutationReceiptV1
    ) throws {
        try plan.validate()
        try mutationReceipt.validate()
        let identity = try plan.basis.mutation.affectedIdentity
        let expected = try MutationPortableExpectedRevisionV1(
            plan.basis.expectedRevision
        )
        let expectedByIdentity = Dictionary(
            uniqueKeysWithValues: expected.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        guard mutationReceipt.mutationID == plan.mutationID,
              mutationReceipt.identity.workspaceID == plan.basis.workspaceID,
              mutationReceipt.commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                  WorkspaceCommandV1.applyPartyAccountability(plan.basis.mutation)
              )),
              mutationReceipt.expectedRevision == expected,
              let expectedEntityRevision = expectedByIdentity[identity],
              expected.workspaceRevision < UInt64.max,
              expectedEntityRevision < UInt64.max,
              mutationReceipt.resultingRevision.workspaceRevision
                  == expected.workspaceRevision + 1,
              mutationReceipt.resultingRevision.entityRevisions.contains(
                  where: {
                      $0.identity == identity
                          && expectedEntityRevision < UInt64.max
                      && $0.revision == expectedEntityRevision + 1
                  }
              ),
              mutationReceipt.postImages.count == 1,
              let postImage = mutationReceipt.postImages.first,
              (try? postImage.identity) == identity,
              postImage.revision == expectedEntityRevision + 1,
              mutationReceipt.sourceKind == .localUser else {
            throw PartyAccountabilityCoordinatorFailureV1.receiptMismatch
        }

        schemaVersion = Self.schemaVersion
        planSHA256 = plan.planSHA256
        self.mutationReceipt = mutationReceipt
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        affectedIdentity = identity
        committedAt = mutationReceipt.committedAt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                planSHA256: plan.planSHA256,
                mutationReceiptIdentity: mutationReceipt.identity,
                mutationReceiptSHA256: mutationReceiptSHA256,
                affectedIdentity: identity,
                committedAt: committedAt
            )
        )
    }

    func validate() throws {
        try mutationReceipt.validate()
        let resultingRevision = mutationReceipt.resultingRevision.entityRevisions
            .first(where: { $0.identity == affectedIdentity })?.revision
        let postImage = mutationReceipt.postImages.first
        guard schemaVersion == Self.schemaVersion,
              MutationEnvelopeV1.isSHA256(planSHA256),
              mutationReceipt.identity == mutationReceiptIdentity,
              mutationReceiptSHA256 == (try mutationReceipt.canonicalSHA256()),
              mutationReceipt.sourceKind == .localUser,
              mutationReceipt.postImages.count == 1,
              let postImage,
              (try? postImage.identity) == affectedIdentity,
              resultingRevision == postImage.revision,
              committedAt == mutationReceipt.committedAt,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                  DigestBasis(
                      schemaVersion: schemaVersion,
                      planSHA256: planSHA256,
                      mutationReceiptIdentity: mutationReceiptIdentity,
                      mutationReceiptSHA256: mutationReceiptSHA256,
                      affectedIdentity: affectedIdentity,
                      committedAt: committedAt
                  )
              )),
              committedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PartyAccountabilityCoordinatorFailureV1.receiptMismatch
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let planSHA256: String
        let mutationReceiptIdentity: MutationReceiptIdentityV1
        let mutationReceiptSHA256: String
        let affectedIdentity: WorkspaceEntityIdentityV1
        let committedAt: Date
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, planSHA256, mutationReceipt,
             mutationReceiptIdentity, mutationReceiptSHA256,
             affectedIdentity, committedAt, receiptSHA256
    }

    init(from decoder: Decoder) throws {
        try PartyAccountabilityCoordinatorClosedCodingV1.require(
            decoder,
            keys: CodingKeys.self
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let receipt = try values.decode(
            MutationReceiptV1.self,
            forKey: .mutationReceipt
        )
        let identity = try values.decode(
            WorkspaceEntityIdentityV1.self,
            forKey: .affectedIdentity
        )
        let expectedIdentity = try values.decode(
            MutationReceiptIdentityV1.self,
            forKey: .mutationReceiptIdentity
        )
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        planSHA256 = try values.decode(String.self, forKey: .planSHA256)
        self.mutationReceipt = receipt
        mutationReceiptIdentity = expectedIdentity
        mutationReceiptSHA256 = try values.decode(
            String.self,
            forKey: .mutationReceiptSHA256
        )
        affectedIdentity = identity
        committedAt = try values.decode(Date.self, forKey: .committedAt)
        receiptSHA256 = try values.decode(String.self, forKey: .receiptSHA256)
        guard mutationReceipt.identity == mutationReceiptIdentity else {
            throw PartyAccountabilityCoordinatorFailureV1.receiptMismatch
        }
        try validate()
    }
}

enum QualificationProjectionStateV1: String, Codable, CaseIterable, Sendable {
    case notYetEffective = "NOT_YET_EFFECTIVE"
    case declared = "DECLARED"
    case expired = "EXPIRED"
}

/// Deterministic, read-only projection for application/report consumers.
/// Values in `actorSnapshots`, `qualificationSnapshots`, and `signoffs` are
/// the exact persisted snapshots; no current-party lookup is used to rewrite
/// historic display.
struct PartyAccountabilityProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let asOf: Date
    let parties: [ServicePartyReferenceV1]
    let siteRoleEvents: [SitePartyRoleEventV1]
    let actorSnapshots: [ActorSnapshotV1]
    let qualificationSnapshots: [QualificationSnapshotV1]
    let signoffs: [SignoffSnapshotV1]
    let projectionSHA256: String

    init(
        workspaceID: WorkspaceID,
        asOf: Date,
        parties: [ServicePartyReferenceV1],
        siteRoleEvents: [SitePartyRoleEventV1],
        actorSnapshots: [ActorSnapshotV1],
        qualificationSnapshots: [QualificationSnapshotV1],
        signoffs: [SignoffSnapshotV1]
    ) throws {
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        let orderedParties = parties.sorted { Self.partyKey($0) < Self.partyKey($1) }
        let orderedRoles = siteRoleEvents.sorted { Self.roleKey($0) < Self.roleKey($1) }
        let orderedActors = actorSnapshots.sorted { Self.actorKey($0) < Self.actorKey($1) }
        let orderedQualifications = qualificationSnapshots.sorted {
            Self.qualificationKey($0) < Self.qualificationKey($1)
        }
        let orderedSignoffs = signoffs.sorted { Self.signoffKey($0) < Self.signoffKey($1) }
        guard orderedParties.map(\.partyID).count
                == Set(orderedParties.map(\.partyID)).count,
              orderedRoles.map(\.eventID).count
                == Set(orderedRoles.map(\.eventID)).count,
              orderedActors.map(\.snapshotID).count
                == Set(orderedActors.map(\.snapshotID)).count,
              orderedQualifications.map(\.snapshotID).count
                == Set(orderedQualifications.map(\.snapshotID)).count,
              orderedSignoffs.map(\.snapshotID).count
                == Set(orderedSignoffs.map(\.snapshotID)).count else {
            throw PartyAccountabilityFailureV1.invalidValue
        }
        try orderedParties.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else {
                throw PartyAccountabilityFailureV1.crossWorkspaceReference
            }
        }
        try orderedRoles.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else {
                throw PartyAccountabilityFailureV1.crossWorkspaceReference
            }
        }
        try orderedActors.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else {
                throw PartyAccountabilityFailureV1.crossWorkspaceReference
            }
        }
        try orderedQualifications.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else {
                throw PartyAccountabilityFailureV1.crossWorkspaceReference
            }
        }
        try orderedSignoffs.forEach {
            try $0.validate()
            guard $0.workspaceID == workspaceID else {
                throw PartyAccountabilityFailureV1.crossWorkspaceReference
            }
        }

        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.asOf = asOf
        parties = orderedParties
        siteRoleEvents = orderedRoles
        self.actorSnapshots = orderedActors
        self.qualificationSnapshots = orderedQualifications
        self.signoffs = orderedSignoffs
        projectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                workspaceID: workspaceID,
                asOf: asOf,
                parties: orderedParties,
                siteRoleEvents: orderedRoles,
                actorSnapshots: orderedActors,
                qualificationSnapshots: orderedQualifications,
                signoffs: orderedSignoffs
            )
        )
    }

    func validate() throws {
        _ = try Self(
            workspaceID: workspaceID,
            asOf: asOf,
            parties: parties,
            siteRoleEvents: siteRoleEvents,
            actorSnapshots: actorSnapshots,
            qualificationSnapshots: qualificationSnapshots,
            signoffs: signoffs
        )
        guard schemaVersion == Self.schemaVersion,
              projectionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                  DigestBasis(
                      schemaVersion: schemaVersion,
                      workspaceID: workspaceID,
                      asOf: asOf,
                      parties: parties,
                      siteRoleEvents: siteRoleEvents,
                      actorSnapshots: actorSnapshots,
                      qualificationSnapshots: qualificationSnapshots,
                      signoffs: signoffs
                  )
              )) else {
            throw PartyAccountabilityFailureV1.digestMismatch
        }
    }

    func effectiveParties() -> [ServicePartyReferenceV1] {
        parties.filter { party in
            party.effectiveAt <= asOf
                && (party.retiredAt.map { asOf <= $0 } ?? true)
        }
    }

    func activeRoles(
        for siteID: UUID,
        at date: Date? = nil
    ) -> [SitePartyRoleEventV1] {
        let instant = date ?? asOf
        let supersededIDs = Set(
            siteRoleEvents.compactMap { value -> UUID? in
                guard let predecessor = value.supersedesEventID,
                      value.effectiveFrom <= instant else { return nil }
                return predecessor
            }
        )
        return siteRoleEvents.filter {
            $0.siteID == siteID
                && $0.effectiveFrom <= instant
                && ($0.effectiveUntil.map { instant <= $0 } ?? true)
                && !supersededIDs.contains($0.eventID)
        }
    }

    func qualificationState(
        _ qualification: QualificationSnapshotV1,
        at date: Date? = nil
    ) -> QualificationProjectionStateV1 {
        let instant = date ?? asOf
        if let effectiveAt = qualification.effectiveAt, instant < effectiveAt {
            return .notYetEffective
        }
        if let expiresAt = qualification.expiresAt, instant > expiresAt {
            return .expired
        }
        return .declared
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let asOf: Date
        let parties: [ServicePartyReferenceV1]
        let siteRoleEvents: [SitePartyRoleEventV1]
        let actorSnapshots: [ActorSnapshotV1]
        let qualificationSnapshots: [QualificationSnapshotV1]
        let signoffs: [SignoffSnapshotV1]
    }

    private static func uuidKey(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private static func partyKey(_ value: ServicePartyReferenceV1) -> String {
        uuidKey(value.partyID)
    }

    private static func roleKey(_ value: SitePartyRoleEventV1) -> String {
        uuidKey(value.eventID)
    }

    private static func actorKey(_ value: ActorSnapshotV1) -> String {
        uuidKey(value.snapshotID)
    }

    private static func qualificationKey(_ value: QualificationSnapshotV1) -> String {
        uuidKey(value.snapshotID)
    }

    private static func signoffKey(_ value: SignoffSnapshotV1) -> String {
        uuidKey(value.snapshotID)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, asOf, parties, siteRoleEvents,
             actorSnapshots, qualificationSnapshots, signoffs, projectionSHA256
    }

    init(from decoder: Decoder) throws {
        try PartyAccountabilityCoordinatorClosedCodingV1.require(
            decoder,
            keys: CodingKeys.self
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = try Self(
            workspaceID: try values.decode(WorkspaceID.self, forKey: .workspaceID),
            asOf: try values.decode(Date.self, forKey: .asOf),
            parties: try values.decode([ServicePartyReferenceV1].self, forKey: .parties),
            siteRoleEvents: try values.decode(
                [SitePartyRoleEventV1].self,
                forKey: .siteRoleEvents
            ),
            actorSnapshots: try values.decode(
                [ActorSnapshotV1].self,
                forKey: .actorSnapshots
            ),
            qualificationSnapshots: try values.decode(
                [QualificationSnapshotV1].self,
                forKey: .qualificationSnapshots
            ),
            signoffs: try values.decode(
                [SignoffSnapshotV1].self,
                forKey: .signoffs
            )
        )
        guard try values.decode(Int.self, forKey: .schemaVersion)
                == Self.schemaVersion,
              try values.decode(String.self, forKey: .projectionSHA256)
                == rebuilt.projectionSHA256 else {
            throw PartyAccountabilityFailureV1.digestMismatch
        }
        self = rebuilt
    }
}

/// The coordinator is the only application seam that turns a validated C38
/// mutation into a WorkspaceWriter request.  The optional lifecycle port is
/// deliberately read/validation-only; it cannot perform an independent
/// persistence write.
@MainActor
protocol PartyAccountabilityLifecyclePortV1: AnyObject {
    func validate(_ mutation: PartyAccountabilityMutationV1) throws
}

@MainActor
final class PartyAccountabilityCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let idSource: any ApplicationIDSource
    private let lifecycle: (any PartyAccountabilityLifecyclePortV1)?

    init(
        writer: WorkspaceWriterV1,
        idSource: any ApplicationIDSource,
        lifecycle: (any PartyAccountabilityLifecyclePortV1)? = nil
    ) {
        self.writer = writer
        self.idSource = idSource
        self.lifecycle = lifecycle
    }

    func makeMutationID() throws -> MutationIDV1 {
        try writer.makeMutationID()
    }

    func preview(
        _ basis: PartyAccountabilityPreviewBasisV1
    ) throws -> PartyAccountabilityChangePlanV1 {
        try basis.validate()
        let observedBefore = try writer.currentRevision()
        let normalizedBasis = try Self.normalizedBasis(
            basis,
            observed: observedBefore
        )
        guard Self.revisionsMatchForPreview(
            observedBefore,
            expected: normalizedBasis.expectedRevision,
            target: try basis.mutation.affectedIdentity
        ) else {
            throw PartyAccountabilityCoordinatorFailureV1.staleRevision
        }
        try lifecycle?.validate(normalizedBasis.mutation)
        guard try writer.currentRevision() == observedBefore else {
            throw PartyAccountabilityCoordinatorFailureV1.staleRevision
        }
        let mutationID = normalizedBasis.mutation.mutationID ?? (try writer.makeMutationID())
        let plan = try PartyAccountabilityChangePlanV1(
            operationID: idSource.makeID(),
            mutationID: mutationID,
            basis: normalizedBasis
        )
        guard try writer.currentRevision() == observedBefore else {
            throw PartyAccountabilityCoordinatorFailureV1.staleRevision
        }
        return plan
    }

    func preview(
        mutation: PartyAccountabilityMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        workspaceID: WorkspaceID
    ) throws -> PartyAccountabilityChangePlanV1 {
        try preview(
            PartyAccountabilityPreviewBasisV1(
                workspaceID: workspaceID,
                expectedRevision: expectedRevision,
                mutation: mutation
            )
        )
    }

    func commit(
        _ plan: PartyAccountabilityChangePlanV1
    ) throws -> PartyAccountabilityChangeReceiptV1 {
        try plan.validate()
        if let durableReceipt = try writer.durableReceipt(
            mutationID: plan.mutationID
        ) {
            return try PartyAccountabilityChangeReceiptV1(
                plan: plan,
                mutationReceipt: durableReceipt
            )
        }
        try lifecycle?.validate(plan.basis.mutation)
        let request = WorkspaceMutationRequestV1(
            mutationID: plan.mutationID,
            expectedRevision: plan.basis.expectedRevision,
            command: .applyPartyAccountability(plan.basis.mutation)
        )
        _ = try writer.execute(request)
        guard let durableReceipt = try writer.durableReceipt(
            mutationID: plan.mutationID
        ) else {
            throw PartyAccountabilityCoordinatorFailureV1.missingDurableReceipt
        }
        return try PartyAccountabilityChangeReceiptV1(
            plan: plan,
            mutationReceipt: durableReceipt
        )
    }

    private static func normalizedBasis(
        _ basis: PartyAccountabilityPreviewBasisV1,
        observed: WorkspaceRevisionV1
    ) throws -> PartyAccountabilityPreviewBasisV1 {
        let target = try basis.mutation.affectedIdentity
        var revisions = basis.expectedRevision.entityRevisions
        if !revisions.contains(where: { $0.identity == target }) {
            revisions.append(WorkspaceEntityRevisionV1(identity: target, revision: 0))
        }
        let expected: WorkspaceExpectedRevisionV1
        do {
            expected = try WorkspaceExpectedRevisionV1(
                workspaceID: basis.expectedRevision.workspaceID,
                generationID: basis.expectedRevision.generationID,
                writerInstanceID: basis.expectedRevision.writerInstanceID,
                workspaceRevision: basis.expectedRevision.workspaceRevision,
                entityRevisions: revisions
            )
        } catch {
            throw PartyAccountabilityCoordinatorFailureV1.invalidPlan
        }
        guard expected.workspaceID == observed.workspaceID,
              expected.generationID == observed.generationID,
              expected.writerInstanceID == observed.writerInstanceID,
              expected.workspaceRevision == observed.revision else {
            throw PartyAccountabilityCoordinatorFailureV1.staleRevision
        }
        return try PartyAccountabilityPreviewBasisV1(
            workspaceID: basis.workspaceID,
            expectedRevision: expected,
            mutation: basis.mutation
        )
    }

    private static func revisionsMatchForPreview(
        _ observed: WorkspaceRevisionV1,
        expected: WorkspaceExpectedRevisionV1,
        target: WorkspaceEntityIdentityV1
    ) -> Bool {
        guard observed.workspaceID == expected.workspaceID,
              observed.generationID == expected.generationID,
              observed.writerInstanceID == expected.writerInstanceID,
              observed.revision == expected.workspaceRevision else {
            return false
        }
        let observedByIdentity = Dictionary(
            uniqueKeysWithValues: observed.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let expectedByIdentity = Dictionary(
            uniqueKeysWithValues: expected.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let nonTargetIdentities = Set(observedByIdentity.keys)
            .union(expectedByIdentity.keys)
            .subtracting([target])
        guard nonTargetIdentities.allSatisfy({
            observedByIdentity[$0] == expectedByIdentity[$0]
        }) else {
            return false
        }
        return observedByIdentity[target, default: 0]
            == expectedByIdentity[target, default: 0]
    }
}

// Compatibility spellings used by neighboring application slices.
typealias PartyAccountabilityPlanV1 = PartyAccountabilityChangePlanV1
typealias PartyAccountabilityReceiptV1 = PartyAccountabilityChangeReceiptV1
