import Foundation

private enum SignoffEnrollmentClosedCodingV1 {
    static func require<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        keys: Key.Type
    ) throws where Key.AllCases: Collection {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let actual = Set(raw.allKeys.map(\.stringValue))
        let allowed = Set(Key.allCases.map(\.stringValue))
        guard actual == allowed else {
            throw SignoffEnrollmentFailureV1.invalidValue
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

/// Closed, local-only enrollment language for the C43 approval-response
/// affordance.  This is deliberately a response record, never a finding of
/// identity, authority, legal assent, nonrepudiation, final approval, or a
/// workflow transition.
enum SignoffEnrollmentManifestV1: String, Codable, CaseIterable, Hashable, Sendable {
    case workDetailCompletedResponseV1 = "WORK_DETAIL_COMPLETED_RESPONSE_V1"

    static let actionTitle = "Record approval response"

    var purpose: String { rawValue }
}

enum SignoffEnrollmentDrawnMarkV1: String, Codable, CaseIterable, Hashable, Sendable {
    /// Presence is intentionally the entire payload.  Strokes, images,
    /// hashes, timing, pressure, and biometric/template data are forbidden.
    case presentNonBiometric = "PRESENT_NON_BIOMETRIC"
}

enum SignoffEnrollmentFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case unsupportedClaim
    case staleRevision
    case receiptMismatch
}

/// These values are positive prohibitions: every one must remain true.  The
/// type has no initializer that permits callers to relax an individual claim.
struct SignoffEnrollmentProhibitedClaimFlagsV1: Codable, Equatable, Hashable, Sendable {
    let disclaimsVerifiedIdentity: Bool
    let disclaimsVerifiedAuthority: Bool
    let disclaimsBehalfOfAnotherPerson: Bool
    let disclaimsLegalSignature: Bool
    let disclaimsLegalEffect: Bool
    let disclaimsNonrepudiation: Bool
    let disclaimsFinalApproval: Bool
    let disclaimsWorkflowTransition: Bool

    init() {
        disclaimsVerifiedIdentity = true
        disclaimsVerifiedAuthority = true
        disclaimsBehalfOfAnotherPerson = true
        disclaimsLegalSignature = true
        disclaimsLegalEffect = true
        disclaimsNonrepudiation = true
        disclaimsFinalApproval = true
        disclaimsWorkflowTransition = true
    }

    func validate() throws {
        guard disclaimsVerifiedIdentity,
              disclaimsVerifiedAuthority,
              disclaimsBehalfOfAnotherPerson,
              disclaimsLegalSignature,
              disclaimsLegalEffect,
              disclaimsNonrepudiation,
              disclaimsFinalApproval,
              disclaimsWorkflowTransition else {
            throw SignoffEnrollmentFailureV1.unsupportedClaim
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case disclaimsVerifiedIdentity, disclaimsVerifiedAuthority,
             disclaimsBehalfOfAnotherPerson, disclaimsLegalSignature,
             disclaimsLegalEffect, disclaimsNonrepudiation,
             disclaimsFinalApproval, disclaimsWorkflowTransition
    }

    init(from decoder: Decoder) throws {
        try SignoffEnrollmentClosedCodingV1.require(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        guard try values.decode(Bool.self, forKey: .disclaimsVerifiedIdentity)
                == disclaimsVerifiedIdentity,
              try values.decode(Bool.self, forKey: .disclaimsVerifiedAuthority)
                == disclaimsVerifiedAuthority,
              try values.decode(Bool.self, forKey: .disclaimsBehalfOfAnotherPerson)
                == disclaimsBehalfOfAnotherPerson,
              try values.decode(Bool.self, forKey: .disclaimsLegalSignature)
                == disclaimsLegalSignature,
              try values.decode(Bool.self, forKey: .disclaimsLegalEffect)
                == disclaimsLegalEffect,
              try values.decode(Bool.self, forKey: .disclaimsNonrepudiation)
                == disclaimsNonrepudiation,
              try values.decode(Bool.self, forKey: .disclaimsFinalApproval)
                == disclaimsFinalApproval,
              try values.decode(Bool.self, forKey: .disclaimsWorkflowTransition)
                == disclaimsWorkflowTransition else {
            throw SignoffEnrollmentFailureV1.unsupportedClaim
        }
    }
}

/// A fixed disclosure, rather than caller-provided legal or identity wording.
struct SignoffEnrollmentDisclosureV1: Codable, Equatable, Hashable, Sendable {
    static let releaseID = "work-detail-completed-response.local-v1"
    static let disclosureText = "Recorded locally as a typed response. Identity and authority are not verified, and this does not respond on behalf of another person. It is not a legal signature, legal effect, nonrepudiable record, final approval, or workflow transition."

    let releaseID: String
    let disclosureText: String
    let prohibitedClaims: SignoffEnrollmentProhibitedClaimFlagsV1

    init() {
        releaseID = Self.releaseID
        disclosureText = Self.disclosureText
        prohibitedClaims = SignoffEnrollmentProhibitedClaimFlagsV1()
    }

    func validate() throws {
        try prohibitedClaims.validate()
        guard releaseID == Self.releaseID,
              disclosureText == Self.disclosureText else {
            throw SignoffEnrollmentFailureV1.unsupportedClaim
        }
    }

    func partyDisclosureRelease() throws -> SignoffIntentDisclosureReleaseV1 {
        try validate()
        return try SignoffIntentDisclosureReleaseV1(
            releaseID: releaseID,
            disclosureText: disclosureText,
            statesLocalAssertionOnly: true,
            disclaimsIdentityVerification: true,
            disclaimsLegalSignature: true
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case releaseID, disclosureText, prohibitedClaims
    }

    init(from decoder: Decoder) throws {
        try SignoffEnrollmentClosedCodingV1.require(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        guard try values.decode(String.self, forKey: .releaseID) == releaseID,
              try values.decode(String.self, forKey: .disclosureText) == disclosureText,
              try values.decode(
                SignoffEnrollmentProhibitedClaimFlagsV1.self,
                forKey: .prohibitedClaims
              ) == prohibitedClaims else {
            throw SignoffEnrollmentFailureV1.unsupportedClaim
        }
    }
}

/// Records only the route facts C43 uses to prove that response recording is
/// offered from Work.  It does not restore or persist a navigation route.
struct SignoffEnrollmentRouteChainTruthV1: Codable, Equatable, Hashable, Sendable {
    let actionRoot: AppRootV1
    let editorDestination: NavigationDestinationV1
    let editorRoot: AppRootV1
    let historyDestination: NavigationDestinationV1
    let historyRoot: AppRootV1
    let requiresVisibleWorkRoot: Bool
    let directDeepLinkOnlyIsEligible: Bool

    init() {
        actionRoot = .work
        editorDestination = .signoffEditor
        editorRoot = .work
        historyDestination = .signoffHistory
        historyRoot = .reports
        requiresVisibleWorkRoot = true
        directDeepLinkOnlyIsEligible = false
    }

    func validate() throws {
        guard actionRoot == .work,
              editorDestination == .signoffEditor,
              editorRoot == RouteRegistryV1.root(for: editorDestination),
              historyDestination == .signoffHistory,
              historyRoot == RouteRegistryV1.root(for: historyDestination),
              requiresVisibleWorkRoot,
              !directDeepLinkOnlyIsEligible else {
            throw SignoffEnrollmentFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case actionRoot, editorDestination, editorRoot, historyDestination, historyRoot,
             requiresVisibleWorkRoot, directDeepLinkOnlyIsEligible
    }

    init(from decoder: Decoder) throws {
        try SignoffEnrollmentClosedCodingV1.require(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        guard try values.decode(AppRootV1.self, forKey: .actionRoot) == actionRoot,
              try values.decode(NavigationDestinationV1.self, forKey: .editorDestination)
                == editorDestination,
              try values.decode(AppRootV1.self, forKey: .editorRoot) == editorRoot,
              try values.decode(NavigationDestinationV1.self, forKey: .historyDestination)
                == historyDestination,
              try values.decode(AppRootV1.self, forKey: .historyRoot) == historyRoot,
              try values.decode(Bool.self, forKey: .requiresVisibleWorkRoot)
                == requiresVisibleWorkRoot,
              try values.decode(Bool.self, forKey: .directDeepLinkOnlyIsEligible)
                == directDeepLinkOnlyIsEligible else {
            throw SignoffEnrollmentFailureV1.invalidValue
        }
    }
}

/// Ephemeral UI/application input. `drawnMark` carries no mark bytes and is
/// not retained by the plan or receipt; only its presence chooses the existing
/// Signoff method.
struct SignoffEnrollmentRequestV1: Equatable, Sendable {
    let manifest: SignoffEnrollmentManifestV1
    let workspaceID: WorkspaceID
    let subjectID: UUID
    let subjectRevision: UInt64
    let expectedRevision: WorkspaceExpectedRevisionV1
    let actorSnapshot: ActorSnapshotV1
    let typedName: String
    let claimedRole: String
    let claimedRelationship: SitePartyRoleV1?
    let disclosure: SignoffEnrollmentDisclosureV1
    let routeChain: SignoffEnrollmentRouteChainTruthV1
    let occurredAt: Date
    let recordedAt: Date
    let drawnMark: SignoffEnrollmentDrawnMarkV1?
    let mutationID: MutationIDV1?

    init(
        manifest: SignoffEnrollmentManifestV1 = .workDetailCompletedResponseV1,
        workspaceID: WorkspaceID,
        subjectID: UUID,
        subjectRevision: UInt64,
        expectedRevision: WorkspaceExpectedRevisionV1,
        actorSnapshot: ActorSnapshotV1,
        typedName: String,
        claimedRole: String,
        claimedRelationship: SitePartyRoleV1? = nil,
        disclosure: SignoffEnrollmentDisclosureV1 = SignoffEnrollmentDisclosureV1(),
        routeChain: SignoffEnrollmentRouteChainTruthV1 = SignoffEnrollmentRouteChainTruthV1(),
        occurredAt: Date,
        recordedAt: Date,
        drawnMark: SignoffEnrollmentDrawnMarkV1? = nil,
        mutationID: MutationIDV1? = nil
    ) throws {
        self.manifest = manifest
        self.workspaceID = workspaceID
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
        self.expectedRevision = expectedRevision
        self.actorSnapshot = actorSnapshot
        self.typedName = typedName
        self.claimedRole = claimedRole
        self.claimedRelationship = claimedRelationship
        self.disclosure = disclosure
        self.routeChain = routeChain
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.drawnMark = drawnMark
        self.mutationID = mutationID
        try validate()
    }

    func validate() throws {
        try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        try PartyAccountabilityValidationV1.requireID(subjectID)
        try PartyAccountabilityValidationV1.requireText(
            typedName,
            maximumBytes: PartyAccountabilityLimitsV1.maximumDisplayNameBytes
        )
        try PartyAccountabilityValidationV1.requireText(
            claimedRole,
            maximumBytes: PartyAccountabilityLimitsV1.maximumDisplayNameBytes
        )
        try PartyAccountabilityValidationV1.requireFiniteDate(occurredAt)
        try PartyAccountabilityValidationV1.requireFiniteDate(recordedAt)
        try actorSnapshot.validate()
        try disclosure.validate()
        try routeChain.validate()
        guard manifest == .workDetailCompletedResponseV1,
              subjectRevision > 0,
              expectedRevision.workspaceID == workspaceID,
              actorSnapshot.workspaceID == workspaceID,
              typedName == actorSnapshot.displayNameAtTime,
              typedName == actorSnapshot.actor.displayName,
              occurredAt <= recordedAt else {
            throw SignoffEnrollmentFailureV1.invalidValue
        }
    }

    var selectedMethod: SignoffMethodV1 {
        drawnMark == nil ? .typedLocalAssertion : .explicitLocalAcknowledgement
    }
}

/// Durable-recovery plan.  It intentionally carries no drawn-mark value; the
/// canonical Signoff method is the sole durable indication of mark presence.
struct SignoffEnrollmentPlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let manifest: SignoffEnrollmentManifestV1
    let workspaceID: WorkspaceID
    let snapshotID: UUID
    let subjectID: UUID
    let subjectRevision: UInt64
    let method: SignoffMethodV1
    let routeChain: SignoffEnrollmentRouteChainTruthV1
    let partyPlan: PartyAccountabilityChangePlanV1
    let planSHA256: String

    init(
        request: SignoffEnrollmentRequestV1,
        snapshotID: UUID,
        partyPlan: PartyAccountabilityChangePlanV1
    ) throws {
        try request.validate()
        try PartyAccountabilityValidationV1.requireID(snapshotID)
        schemaVersion = Self.schemaVersion
        manifest = request.manifest
        workspaceID = request.workspaceID
        self.snapshotID = snapshotID
        subjectID = request.subjectID
        subjectRevision = request.subjectRevision
        method = request.selectedMethod
        routeChain = request.routeChain
        self.partyPlan = partyPlan
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                manifest: manifest,
                workspaceID: workspaceID,
                snapshotID: snapshotID,
                subjectID: subjectID,
                subjectRevision: subjectRevision,
                method: method,
                routeChain: routeChain,
                requiresVisibleWorkRoot: routeChain.requiresVisibleWorkRoot,
                directDeepLinkOnlyIsEligible: routeChain.directDeepLinkOnlyIsEligible,
                partyPlanSHA256: partyPlan.planSHA256
            )
        )
        try validate()
    }

    func validate() throws {
        try PartyAccountabilityValidationV1.requireWorkspace(workspaceID)
        try PartyAccountabilityValidationV1.requireID(snapshotID)
        try PartyAccountabilityValidationV1.requireID(subjectID)
        try routeChain.validate()
        try partyPlan.validate()
        guard schemaVersion == Self.schemaVersion,
              manifest == .workDetailCompletedResponseV1,
              subjectRevision > 0,
              method == .typedLocalAssertion || method == .explicitLocalAcknowledgement,
              MutationEnvelopeV1.isSHA256(planSHA256),
              planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                DigestBasis(
                    schemaVersion: schemaVersion,
                    manifest: manifest,
                    workspaceID: workspaceID,
                    snapshotID: snapshotID,
                    subjectID: subjectID,
                    subjectRevision: subjectRevision,
                    method: method,
                    routeChain: routeChain,
                    requiresVisibleWorkRoot: routeChain.requiresVisibleWorkRoot,
                    directDeepLinkOnlyIsEligible: routeChain.directDeepLinkOnlyIsEligible,
                    partyPlanSHA256: partyPlan.planSHA256
                )
              )),
              partyPlan.basis.workspaceID == workspaceID,
              partyPlan.basis.expectedRevision.workspaceID == workspaceID,
              case let .appendSignoff(snapshot) = partyPlan.basis.mutation,
              snapshot.snapshotID == snapshotID,
              snapshot.workspaceID == workspaceID,
              snapshot.purpose == manifest.purpose,
              snapshot.subjectID == subjectID,
              snapshot.subjectRevision == subjectRevision,
              snapshot.disposition == .recordedLocalAssertion,
              snapshot.method == method,
              snapshot.qualification == nil,
              snapshot.externalEvidenceID == nil,
              snapshot.supersedesSnapshotID == nil,
              snapshot.mutationID == partyPlan.mutationID else {
            throw SignoffEnrollmentFailureV1.invalidValue
        }
        try C43SignoffEnrollmentBoundaryV1.validate(snapshot)
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let manifest: SignoffEnrollmentManifestV1
        let workspaceID: WorkspaceID
        let snapshotID: UUID
        let subjectID: UUID
        let subjectRevision: UInt64
        let method: SignoffMethodV1
        let routeChain: SignoffEnrollmentRouteChainTruthV1
        let requiresVisibleWorkRoot: Bool
        let directDeepLinkOnlyIsEligible: Bool
        let partyPlanSHA256: String
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, manifest, workspaceID, snapshotID, subjectID,
             subjectRevision, method, routeChain, partyPlan, planSHA256
    }

    init(from decoder: Decoder) throws {
        try SignoffEnrollmentClosedCodingV1.require(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        manifest = try values.decode(SignoffEnrollmentManifestV1.self, forKey: .manifest)
        workspaceID = try values.decode(WorkspaceID.self, forKey: .workspaceID)
        snapshotID = try values.decode(UUID.self, forKey: .snapshotID)
        subjectID = try values.decode(UUID.self, forKey: .subjectID)
        subjectRevision = try values.decode(UInt64.self, forKey: .subjectRevision)
        method = try values.decode(SignoffMethodV1.self, forKey: .method)
        routeChain = try values.decode(
            SignoffEnrollmentRouteChainTruthV1.self,
            forKey: .routeChain
        )
        partyPlan = try values.decode(PartyAccountabilityChangePlanV1.self, forKey: .partyPlan)
        planSHA256 = try values.decode(String.self, forKey: .planSHA256)
        try validate()
    }
}

struct SignoffEnrollmentReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let planSHA256: String
    let snapshotID: UUID
    let mutationID: MutationIDV1
    let partyPlanSHA256: String
    let partyReceipt: PartyAccountabilityChangeReceiptV1
    let receiptSHA256: String

    init(
        plan: SignoffEnrollmentPlanV1,
        partyReceipt: PartyAccountabilityChangeReceiptV1
    ) throws {
        try plan.validate()
        try partyReceipt.validate()
        schemaVersion = Self.schemaVersion
        planSHA256 = plan.planSHA256
        snapshotID = plan.snapshotID
        mutationID = plan.partyPlan.mutationID
        partyPlanSHA256 = plan.partyPlan.planSHA256
        self.partyReceipt = partyReceipt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                planSHA256: planSHA256,
                snapshotID: snapshotID,
                mutationID: mutationID,
                partyPlanSHA256: partyPlanSHA256,
                partyReceiptSHA256: partyReceipt.receiptSHA256
            )
        )
        try validate()
    }

    func validate() throws {
        try partyReceipt.validate()
        let expectedIdentity = try WorkspaceEntityIdentityV1(
            kind: .signoffSnapshot,
            id: snapshotID
        )
        guard schemaVersion == Self.schemaVersion,
              MutationEnvelopeV1.isSHA256(planSHA256),
              MutationEnvelopeV1.isSHA256(partyPlanSHA256),
              MutationEnvelopeV1.isSHA256(receiptSHA256),
              partyReceipt.planSHA256 == partyPlanSHA256,
              partyReceipt.affectedIdentity == expectedIdentity,
              partyReceipt.mutationReceipt.mutationID == mutationID,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                DigestBasis(
                    schemaVersion: schemaVersion,
                    planSHA256: planSHA256,
                    snapshotID: snapshotID,
                    mutationID: mutationID,
                    partyPlanSHA256: partyPlanSHA256,
                    partyReceiptSHA256: partyReceipt.receiptSHA256
                )
              )) else {
            throw SignoffEnrollmentFailureV1.receiptMismatch
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let planSHA256: String
        let snapshotID: UUID
        let mutationID: MutationIDV1
        let partyPlanSHA256: String
        let partyReceiptSHA256: String
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, planSHA256, snapshotID, mutationID, partyPlanSHA256,
             partyReceipt, receiptSHA256
    }

    init(from decoder: Decoder) throws {
        try SignoffEnrollmentClosedCodingV1.require(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        planSHA256 = try values.decode(String.self, forKey: .planSHA256)
        snapshotID = try values.decode(UUID.self, forKey: .snapshotID)
        mutationID = try values.decode(MutationIDV1.self, forKey: .mutationID)
        partyPlanSHA256 = try values.decode(String.self, forKey: .partyPlanSHA256)
        partyReceipt = try values.decode(
            PartyAccountabilityChangeReceiptV1.self,
            forKey: .partyReceipt
        )
        receiptSHA256 = try values.decode(String.self, forKey: .receiptSHA256)
        try validate()
    }
}
